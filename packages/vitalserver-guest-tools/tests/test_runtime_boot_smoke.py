from __future__ import annotations

import json
import subprocess
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest

from tirosh_guest_tools.application import runtime_boot_smoke
from tirosh_guest_tools.application.runtime_boot_smoke import (
    RUNTIME_BOOT_SMOKE_MANIFEST,
    RuntimeBootSmokeContext,
    RuntimeBootSmokeOperations,
    RuntimeBootSmokeRun,
    default_context,
    run_runtime_boot_smoke,
)
from tirosh_guest_tools.infrastructure.common import read_json, write_json

NOW = datetime(2026, 6, 11, 12, 0, tzinfo=UTC)


def test_runtime_boot_smoke_writes_manifest_for_success(tmp_path: Path) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)

    run_runtime_boot_smoke(context=context, operations=fake_operations())

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["schemaVersion"] == 1
    assert document["runId"] == "runtime-run-test"
    assert document["status"] == "passed"
    assert stage_status(document, "bootstrap-result") == "passed"
    assert stage_status(document, "runtime-observation") == "passed"
    assert stage_status(document, "systemd-units") == "passed"
    assert stage_status(document, "runtime-data") == "passed"
    assert (
        stage_details(document, "runtime-data")["dockerDataRoot"]
        == "/mnt/runtime/docker"
    )
    assert stage_status(document, "http") == "passed"
    assert stage_status(document, "compose-services") == "passed"
    assert stage_status(document, "guest-control-api") == "passed"
    guest_control_operation = stage_details(document, "guest-control-api")["operation"]
    assert isinstance(guest_control_operation, dict)
    assert guest_control_operation["operationId"] == "op_app_restart_smoke"
    reconcile_operation = stage_details(document, "guest-control-api")[
        "reconcileOperation"
    ]
    assert isinstance(reconcile_operation, dict)
    assert reconcile_operation["operationId"] == "op_stack_reconcile_smoke"
    lab_scenarios = stage_details(document, "guest-control-api")["labScenarios"]
    assert lab_scenarios == {
        "state": "loaded",
        "scenarios": [
            {
                "scenarioId": "normal_monitoring",
                "name": "Normal monitoring",
            }
        ],
    }
    lab_session_operations = stage_details(
        document,
        "guest-control-api",
    )["labSessionOperations"]
    assert isinstance(lab_session_operations, dict)
    assert lab_session_operations["scenarioId"] == "normal_monitoring"
    assert lab_session_operations["sessionId"] == "lab-session-1"
    assert lab_session_operations["operationIds"] == [
        "op_lab_create_smoke",
        "op_lab_start_smoke",
        "op_lab_stop_smoke",
        "op_lab_replay_smoke",
    ]
    assert stage_status(document, "disk-health") == "passed"
    assert stage_status(document, "capabilities") == "passed"
    assert stage_status(document, "runtime-share") == "passed"
    assert stage_status(document, "feature-readiness") == "passed"


def test_runtime_boot_smoke_uses_operation_timeout_for_guest_restart(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)
    observed_timeouts: list[tuple[str, str, float]] = []
    guest_control_http_json = fake_guest_control_http_json(
        observed_timeouts=observed_timeouts,
    )

    run_runtime_boot_smoke(
        context=context,
        operations=fake_operations(http_json=guest_control_http_json),
    )

    restart_requests = [
        timeout
        for method, url, timeout in observed_timeouts
        if method == "POST" and url.endswith("/v1/services/app/restart")
    ]
    assert restart_requests == [
        runtime_boot_smoke.GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS,
    ]
    reconcile_requests = [
        timeout
        for method, url, timeout in observed_timeouts
        if method == "POST" and url.endswith("/v1/stack/reconcile")
    ]
    assert reconcile_requests == [
        runtime_boot_smoke.GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS,
    ]


@pytest.mark.parametrize(
    ("mutate", "expected_message"),
    [
        (
            lambda context: update_json(
                context.runtime_dir / "bootstrap-result.json",
                {"status": "running"},
            ),
            "bootstrap result is not completed",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "bootstrap-result.json",
                {"status": "failed", "reasonCodes": ["guest-bootstrap-failed"]},
            ),
            "bootstrap result is not completed",
        ),
        (
            lambda context: (context.runtime_dir / "runtime-observation.json").unlink(),
            "No such file or directory",
        ),
        (
            lambda context: (
                context.runtime_dir / "runtime-observation.json"
            ).write_text(
                "{",
                encoding="utf-8",
            ),
            "Expecting property name",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "runtime-observation.json",
                {"updatedAt": timestamp(NOW - timedelta(minutes=10))},
            ),
            "runtime observation is stale",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "runtime-observation.json",
                {"bootID": ""},
            ),
            "runtime observation bootID is missing",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "runtime-observation.json",
                {"diskHealth": {"rootFilesystemReadOnly": True, "kernelErrors": []}},
            ),
            "root filesystem is not explicitly writable",
        ),
    ],
)
def test_runtime_boot_smoke_rejects_invalid_contracts(
    tmp_path: Path,
    mutate: Callable[[RuntimeBootSmokeContext], None],
    expected_message: str,
) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)
    mutate(context)

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(context=context, operations=fake_operations())

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["status"] == "failed"
    assert expected_message in failed_stage_message(document)


def test_runtime_boot_smoke_rejects_inactive_systemd_unit(tmp_path: Path) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(
            context=context,
            operations=fake_operations(inactive_service="tirosh-runtime-observation.service"),
        )

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert "required systemd unit is not active" in failed_stage_message(document)


def test_runtime_boot_smoke_rejects_wrong_docker_data_root(tmp_path: Path) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(
            context=context,
            operations=fake_operations(docker_root="/var/lib/docker"),
        )

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert "Docker data-root does not match" in failed_stage_message(document)


def test_runtime_boot_smoke_rejects_unready_http(tmp_path: Path) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(
            context=context,
            operations=fake_operations(http_status=lambda url, timeout_seconds: 503),
        )

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert "runtime HTTP endpoint is not ready" in failed_stage_message(document)


def test_runtime_boot_smoke_rejects_unready_guest_control_api(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)

    def failing_http_json(
        method: str,
        url: str,
        timeout_seconds: float,
        body: dict[str, Any] | None,
        ) -> dict[str, Any]:
            del method
            del timeout_seconds
            del body
            if url.endswith("/v1/stack/status"):
                return {
                    "state": "loaded",
                    "observedAt": timestamp(NOW),
                    "services": default_stack_status_services(),
                }
            if url.endswith("/ready"):
                return {"status": "starting"}
            raise AssertionError(f"unexpected URL after failed ready probe: {url}")

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(
            context=context,
            operations=fake_operations(http_json=failing_http_json),
        )

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert stage_status(document, "guest-control-api") == "failed"
    assert "guest control API is not ready" in failed_stage_message(document)


@pytest.mark.parametrize("health", [None, "", "starting", "unhealthy"])
def test_runtime_boot_smoke_rejects_service_without_explicit_healthy_status(
    tmp_path: Path,
    health: object,
) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)
    stack_services = default_stack_status_services()
    stack_services[0]["health"] = health

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(
            context=context,
            operations=fake_operations(
                http_json=fake_guest_control_http_json(
                    stack_services=stack_services,
                ),
            ),
        )

    manifest = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert "compose services are not ready" in failed_stage_message(manifest)


def test_runtime_boot_smoke_waits_for_compose_service_to_become_healthy(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(tmp_path, compose_ready_timeout_seconds=10)
    write_valid_runtime_documents(context)
    stack_services = default_stack_status_services()
    stack_services[0]["health"] = "starting"

    def mark_healthy(seconds: float) -> None:
        stack_services[0]["health"] = "healthy"

    run_runtime_boot_smoke(
        context=context,
        operations=fake_operations(
            http_json=fake_guest_control_http_json(
                stack_services=stack_services,
            ),
            sleep=mark_healthy,
        ),
    )

    manifest = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert manifest["status"] == "passed"
    assert stage_status(manifest, "compose-services") == "passed"


def test_runtime_boot_smoke_waits_for_missing_compose_service_to_appear(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(
        tmp_path,
        compose_ready_timeout_seconds=10,
    )
    write_valid_runtime_documents(context)
    stack_services = [
        service
        for service in default_stack_status_services()
        if service["service"] != "lab"
    ]

    def add_lab(seconds: float) -> None:
        stack_services.append(
            {
                "service": "lab",
                "exitCode": 0,
                "health": "healthy",
                "observedAt": timestamp(NOW),
                "state": "running",
            }
        )

    run_runtime_boot_smoke(
        context=context,
        operations=fake_operations(
            http_json=fake_guest_control_http_json(
                stack_services=stack_services,
            ),
            sleep=add_lab,
        ),
    )

    manifest = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert manifest["status"] == "passed"
    assert stage_status(manifest, "compose-services") == "passed"


def test_runtime_boot_smoke_uses_guest_control_capabilities_after_compose_wait(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(tmp_path, compose_ready_timeout_seconds=10)
    write_valid_runtime_documents(context)
    stack_services = default_stack_status_services()
    stack_services[0]["health"] = "starting"
    capabilities = default_guest_control_capabilities()

    def mark_healthy_and_remove_capability(seconds: float) -> None:
        stack_services[0]["health"] = "healthy"
        capabilities.remove("maintenance:redis-backup:create")

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(
            context=context,
            operations=fake_operations(
                http_json=fake_guest_control_http_json(
                    stack_services=stack_services,
                    capabilities=capabilities,
                ),
                sleep=mark_healthy_and_remove_capability,
            ),
        )

    manifest = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert stage_status(manifest, "compose-services") == "passed"
    assert stage_status(manifest, "guest-control-api") == "failed"
    assert "guest control API capability is missing" in failed_stage_message(manifest)


def test_lab_replay_smoke_file_prepare_uses_runtime_run_contract(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(tmp_path)
    calls: list[tuple[list[str], dict[str, object]]] = []

    def run(
        arguments: list[str],
        *,
        check: bool,
        capture_output: bool,
    ) -> subprocess.CompletedProcess[str]:
        calls.append((arguments, {"check": check, "capture_output": capture_output}))
        return subprocess.CompletedProcess(arguments, 0, "", "")

    operations = fake_operations()
    strict_operations = RuntimeBootSmokeOperations(
        mount_runtime_share=operations.mount_runtime_share,
        read_json=operations.read_json,
        write_json=operations.write_json,
        run=run,
        http_status=operations.http_status,
        http_json=operations.http_json,
        now=operations.now,
        sleep=operations.sleep,
    )
    active_run = RuntimeBootSmokeRun(
        context=context,
        operations=strict_operations,
    )

    path = runtime_boot_smoke.prepare_lab_replay_smoke_vital_file(active_run)

    assert path == runtime_boot_smoke.LAB_REPLAY_SMOKE_VITAL_FILE
    assert calls
    assert calls[0][1] == {"check": False, "capture_output": True}


def test_runtime_boot_smoke_rejects_missing_product_lab_service_after_timeout(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)
    stack_services = [
        service
        for service in default_stack_status_services()
        if service["service"] != "lab"
    ]

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(
            context=context,
            operations=fake_operations(
                http_json=fake_guest_control_http_json(
                    stack_services=stack_services,
                ),
            ),
        )

    manifest = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert "guest control stack status is missing services" in failed_stage_message(
        manifest
    )
    assert "lab" in failed_stage_message(manifest)


def test_runtime_boot_smoke_cli_is_registered() -> None:
    pyproject = Path(__file__).parents[1] / "pyproject.toml"
    assert "tirosh-vitalserver-runtime-boot-smoke" in pyproject.read_text(
        encoding="utf-8"
    )


def test_runtime_boot_smoke_default_context_reads_explicit_metadata(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    deploy_dir = tmp_path / "deploy"
    runtime_dir = tmp_path / "run"
    deploy_dir.mkdir()
    runtime_dir.mkdir()
    write_default_context_documents(deploy_dir, run_id="explicit-run")
    monkeypatch.setattr(runtime_boot_smoke, "DEPLOY_DIR", deploy_dir)
    monkeypatch.setattr(runtime_boot_smoke, "RUNTIME_DIR", runtime_dir)

    context = default_context()

    assert context.run_id == "explicit-run"
    assert context.dev_build is False
    assert context.manifest_path == runtime_dir / RUNTIME_BOOT_SMOKE_MANIFEST


@pytest.mark.parametrize(
    ("mutate", "expected_message"),
    [
        (
            lambda deploy_dir: (deploy_dir / "runtime-config.json").unlink(),
            "runtime config is missing",
        ),
        (
            lambda deploy_dir: (deploy_dir / "runtime-config.json").write_text(
                "{",
                encoding="utf-8",
            ),
            "runtime config is invalid JSON",
        ),
        (
            lambda deploy_dir: (deploy_dir / "runtime-config.json").write_text(
                "[]",
                encoding="utf-8",
            ),
            "runtime config must be a JSON object",
        ),
        (
            lambda deploy_dir: (
                deploy_dir / "build-metadata/rootfs-input.json"
            ).unlink(),
            "runtime boot smoke metadata is missing",
        ),
        (
            lambda deploy_dir: (
                deploy_dir / "build-metadata/rootfs-input.json"
            ).write_text("{", encoding="utf-8"),
            "runtime boot smoke metadata is invalid JSON",
        ),
        (
            lambda deploy_dir: update_json(
                deploy_dir / "build-metadata/rootfs-input.json",
                {"runtimeBootSmoke": {"enabled": False, "runId": "explicit-run"}},
            ),
            "runtime boot smoke is not explicitly enabled",
        ),
        (
            lambda deploy_dir: update_json(
                deploy_dir / "build-metadata/rootfs-input.json",
                {"runtimeBootSmoke": {"enabled": True}},
            ),
            "runtime boot smoke runId is missing",
        ),
    ],
)
def test_runtime_boot_smoke_default_context_rejects_missing_or_invalid_inputs(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    mutate: Callable[[Path], None],
    expected_message: str,
) -> None:
    deploy_dir = tmp_path / "deploy"
    runtime_dir = tmp_path / "run"
    deploy_dir.mkdir()
    runtime_dir.mkdir()
    write_default_context_documents(deploy_dir, run_id="explicit-run")
    mutate(deploy_dir)
    monkeypatch.setattr(runtime_boot_smoke, "DEPLOY_DIR", deploy_dir)
    monkeypatch.setattr(runtime_boot_smoke, "RUNTIME_DIR", runtime_dir)

    with pytest.raises(RuntimeError, match=expected_message):
        default_context()


def runtime_boot_context(
    tmp_path: Path,
    *,
    compose_ready_timeout_seconds: float = 0,
    dev_build: bool = False,
) -> RuntimeBootSmokeContext:
    runtime_dir = tmp_path / "run"
    deploy_dir = tmp_path / "deploy"
    runtime_dir.mkdir(parents=True)
    deploy_dir.mkdir(parents=True)
    return RuntimeBootSmokeContext(
        runtime_dir=runtime_dir,
        deploy_dir=deploy_dir,
        manifest_path=runtime_dir / RUNTIME_BOOT_SMOKE_MANIFEST,
        run_id="runtime-run-test",
        max_runtime_observation_age_seconds=180,
        compose_ready_timeout_seconds=compose_ready_timeout_seconds,
        dev_build=dev_build,
    )


def write_valid_runtime_documents(
    context: RuntimeBootSmokeContext,
) -> None:
    write_json(
        context.runtime_dir / "bootstrap-result.json",
        {
            "bootID": "boot-test",
            "message": "Guest bootstrap completed.",
            "operation": "bootstrap",
            "reasonCodes": [],
            "schemaVersion": 3,
            "status": "completed",
            "updatedAt": timestamp(NOW),
        },
    )
    write_json(
        context.runtime_dir / "runtime-observation.json",
        {
            "schemaVersion": 1,
            "bootID": "boot-test",
            "vmIP": "192.168.64.2",
            "updatedAt": timestamp(NOW),
            "probeErrors": [],
            "diskHealth": {
                "rootFilesystemReadOnly": False,
                "kernelErrors": [],
            },
            "httpProbes": {
                "guestHTTP": {"status": "200"},
                "redisUIHTTP": {"status": "200"},
                "swaggerUIHTTP": {"status": "200"},
            },
        },
    )
    write_json(
        context.deploy_dir / "runtime-config.json",
        {
            "publicHost": "127.0.0.1",
            "publicPort": 18080,
            "vitalFilesDirectory": "/mnt/tirosh-vital-files",
        },
    )
    write_json(
        context.deploy_dir / "build-metadata/rootfs-input.json",
        {
            "runtimeData": {
                "diskImageName": "runtime-data.img",
                "diskSize": "16G",
                "filesystemLabel": "vital-runtime",
                "mountPath": "/mnt/runtime",
                "dockerDataRoot": "/mnt/runtime/docker",
                "containerdRoot": "/mnt/runtime/containerd",
            },
        },
    )


def write_default_context_documents(deploy_dir: Path, *, run_id: str) -> None:
    write_json(
        deploy_dir / "runtime-config.json",
        {
            "publicHost": "127.0.0.1",
            "publicPort": 18080,
            "vitalFilesDirectory": "/mnt/tirosh-vital-files",
        },
    )
    write_json(
        deploy_dir / "build-metadata/rootfs-input.json",
        {
            "runtimeBootSmoke": {
                "enabled": True,
                "runId": run_id,
            },
        },
    )


def default_stack_status_services() -> list[dict[str, Any]]:
    return [
        {
            "service": name,
            "state": "running",
            "health": "healthy",
            "observedAt": timestamp(NOW),
            "exitCode": 0,
        }
        for name in (
            "postgres",
            "redis",
            "app",
            "recorder-ingress",
            "vitaldb-observer",
            "redis-relay",
            "lab",
            "redis-ui",
            "swagger-ui",
            "edge",
        )
    ]


def default_guest_control_capabilities() -> list[str]:
    return [
        "services:list",
        "services:status",
        "services:start",
        "services:stop",
        "services:restart",
        "stack:reconcile",
        "lab:scenarios",
        "lab:sessions:create",
        "lab:sessions:get",
        "lab:sessions:start",
        "lab:sessions:stop",
        "lab:vital-files:replay",
        "recorder-ingress:status:get",
        "operations:get",
        "maintenance:redis-backup:create",
        "maintenance:redis-restore:create",
        "maintenance:datastore-repair:create",
        "maintenance:update-activation:create",
        "maintenance:update-shutdown:create",
    ]


def fake_operations(
    *,
    inactive_service: str | None = None,
    service_results: dict[str, str] | None = None,
    http_status: Callable[[str, float], int] | None = None,
    http_json: Callable[
        [str, str, float, dict[str, Any] | None],
        dict[str, Any],
    ] | None = None,
    sleep: Callable[[float], None] | None = None,
    docker_root: str = "/mnt/runtime/docker",
) -> RuntimeBootSmokeOperations:
    def run(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments[:2] == ["findmnt", "--json"]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                json.dumps(
                    {
                        "filesystems": [
                            {
                                "target": "/mnt/runtime",
                                "source": "/dev/nvme1n1",
                                "fstype": "ext4",
                            }
                        ]
                    }
                ),
                "",
            )
        if arguments == ["docker", "info", "--format", "{{json .DockerRootDir}}"]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                json.dumps(docker_root),
                "",
            )
        service = arguments[-1]
        if arguments[:2] == ["systemctl", "show"]:
            property_name = ""
            for argument in arguments:
                if argument.startswith("--property="):
                    property_name = argument.removeprefix("--property=")
                    break
            if property_name == "ActiveState":
                value = "inactive" if service == inactive_service else "active"
            elif property_name == "Result":
                value = (service_results or {}).get(service, "success")
            else:
                value = "unknown"
            return subprocess.CompletedProcess(arguments, 0, value + "\n", "")
        return subprocess.CompletedProcess(arguments, 0, "active\n", "")

    return RuntimeBootSmokeOperations(
        mount_runtime_share=lambda: None,
        read_json=read_json,
        write_json=write_json,
        run=run,
        http_status=http_status or (lambda url, timeout_seconds: 200),
        http_json=http_json or fake_guest_control_http_json(),
        now=lambda: NOW,
        sleep=sleep or (lambda seconds: None),
    )


def fake_guest_control_http_json(
    *,
    stack_services: list[dict[str, Any]] | None = None,
    capabilities: list[str] | None = None,
    observed_timeouts: list[tuple[str, str, float]] | None = None,
) -> Callable[[str, str, float, dict[str, Any] | None], dict[str, Any]]:
    operations: dict[str, dict[str, Any]] = {}
    stack_services = (
        stack_services
        if stack_services is not None
        else default_stack_status_services()
    )
    capabilities = (
        capabilities
        if capabilities is not None
        else default_guest_control_capabilities()
    )

    def request(
        method: str,
        url: str,
        timeout_seconds: float,
        body: dict[str, Any] | None,
    ) -> dict[str, Any]:
        if observed_timeouts is not None:
            observed_timeouts.append((method, url, timeout_seconds))
        if method == "GET" and url.endswith("/ready"):
            return {"status": "ready"}
        if method == "GET" and url.endswith("/v1/capabilities"):
            return {
                "schemaVersion": 1,
                "capabilities": capabilities,
            }
        if method == "GET" and url.endswith("/v1/services"):
            return {"services": ["postgres", "redis", "app", "edge"]}
        if method == "GET" and url.endswith("/v1/services/app/status"):
            return {
                "service": "app",
                "state": "running",
                "health": "healthy",
            }
        if method == "GET" and url.endswith("/v1/stack/status"):
            return {
                "state": "loaded",
                "observedAt": timestamp(NOW),
                "services": stack_services,
            }
        if method == "GET" and url.endswith("/v1/recorder-ingress/status"):
            return {
                "readState": "loaded",
                "httpStatus": "200",
                "readError": None,
                "document": {
                    "startedAt": "2026-06-11T12:00:00Z",
                    "uptimeSeconds": 12,
                    "activeRecorderConnections": 1,
                    "recorders": [
                        {
                            "vrcode": "VR_SMOKE",
                            "remoteAddress": "192.0.2.10",
                            "connectedAt": "2026-06-11T12:00:01Z",
                        }
                    ],
                },
            }
        if method == "GET" and url.endswith("/v1/lab/scenarios"):
            return {
                "state": "loaded",
                "scenarios": [
                    {
                        "scenarioId": "normal_monitoring",
                        "name": "Normal monitoring",
                    }
                ],
            }
        if method == "POST" and url.endswith("/v1/lab/sessions"):
            assert body == {
                "scenarioId": "normal_monitoring",
                "name": "RuntimeBootSmokeLab",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            }
            return lab_session_response(
                operation_id="op_lab_create_smoke",
                state="accepted",
            )
        if method == "GET" and url.endswith("/v1/lab/sessions/lab-session-1"):
            return lab_session_response(operation_id=None, state="accepted")
        if method == "POST" and url.endswith("/v1/lab/sessions/lab-session-1/start"):
            return lab_session_response(
                operation_id="op_lab_start_smoke",
                state="running",
            )
        if method == "POST" and url.endswith("/v1/lab/sessions/lab-session-1/stop"):
            return lab_session_response(
                operation_id="op_lab_stop_smoke",
                state="stopped",
            )
        if method == "POST" and url.endswith("/v1/lab/vital-files/replay"):
            assert body == {
                "vitalFilePath": (
                    "/mnt/tirosh-vital-files/runtime-boot-smoke-replay.vital"
                ),
                "sessionName": "RuntimeBootSmokeReplay",
                "targetURL": "http://edge/",
            }
            return lab_session_response(
                operation_id="op_lab_replay_smoke",
                state="accepted",
            )
        if method == "POST" and url.endswith("/v1/services/app/restart"):
            operation = {
                "operationId": "op_app_restart_smoke",
                "service": "app",
                "command": "restart",
                "state": "completed",
            }
            operations["op_app_restart_smoke"] = operation
            return operation
        if method == "POST" and url.endswith("/v1/stack/reconcile"):
            operation = {
                "operationId": "op_stack_reconcile_smoke",
                "service": "guest-stack",
                "command": "reconcile",
                "state": "completed",
            }
            operations["op_stack_reconcile_smoke"] = operation
            return operation
        if method == "GET" and "/v1/operations/" in url:
            operation_id = url.rsplit("/", 1)[-1]
            return operations[operation_id]
        raise AssertionError(f"unexpected guest control request: {method} {url}")

    return request


def lab_session_response(
    *,
    operation_id: str | None,
    state: str,
) -> dict[str, Any]:
    return {
        "state": "loaded",
        "operationId": operation_id,
        "readError": None,
        "session": {
            "sessionId": "lab-session-1",
            "state": state,
            "scenarioId": "normal_monitoring",
            "name": "RuntimeBootSmokeLab",
            "recorderCount": 1,
            "targetURL": "http://edge/",
            "createdAt": "2026-06-11T12:00:00Z",
            "updatedAt": "2026-06-11T12:00:00Z",
        },
    }


def update_json(path: Path, patch: dict[str, object]) -> None:
    document = json.loads(path.read_text(encoding="utf-8"))
    document.update(patch)
    path.write_text(json.dumps(document), encoding="utf-8")


def timestamp(value: datetime) -> str:
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def stage_status(document: dict[str, object], name: str) -> str:
    stages = document["stages"]
    assert isinstance(stages, list)
    for stage in stages:
        assert isinstance(stage, dict)
        if stage.get("name") == name:
            status = stage.get("status")
            assert isinstance(status, str)
            return status
    raise AssertionError(f"missing stage: {name}")


def stage_details(document: dict[str, object], name: str) -> dict[str, object]:
    stages = document["stages"]
    assert isinstance(stages, list)
    for stage in stages:
        assert isinstance(stage, dict)
        if stage.get("name") == name:
            details = stage.get("details")
            assert isinstance(details, dict)
            return details
    raise AssertionError(f"missing stage: {name}")


def failed_stage_message(document: dict[str, object]) -> str:
    stages = document["stages"]
    assert isinstance(stages, list)
    for stage in stages:
        assert isinstance(stage, dict)
        if stage.get("status") == "failed":
            message = stage.get("message")
            assert isinstance(message, str)
            return message
    raise AssertionError("missing failed stage")
