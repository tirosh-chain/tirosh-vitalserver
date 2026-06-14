from __future__ import annotations

import json
import subprocess
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from tirosh_guest_tools.application import runtime_boot_smoke
from tirosh_guest_tools.application.runtime_boot_smoke import (
    RUNTIME_BOOT_SMOKE_MANIFEST,
    RuntimeBootSmokeContext,
    RuntimeBootSmokeOperations,
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
    assert stage_status(document, "runtime-state") == "passed"
    assert stage_status(document, "systemd-units") == "passed"
    assert stage_status(document, "runtime-data") == "passed"
    assert (
        stage_details(document, "runtime-data")["dockerDataRoot"]
        == "/mnt/runtime/docker"
    )
    assert stage_status(document, "http") == "passed"
    assert stage_status(document, "compose-services") == "passed"
    assert stage_status(document, "disk-health") == "passed"
    assert stage_status(document, "capabilities") == "passed"
    assert stage_status(document, "command-dispatch") == "passed"
    assert stage_status(document, "feature-readiness") == "passed"


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
            lambda context: (context.runtime_dir / "runtime-state.json").unlink(),
            "No such file or directory",
        ),
        (
            lambda context: (context.runtime_dir / "runtime-state.json").write_text(
                "{",
                encoding="utf-8",
            ),
            "Expecting property name",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "runtime-state.json",
                {"updatedAt": timestamp(NOW - timedelta(minutes=10))},
            ),
            "runtime state is stale",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "runtime-state.json",
                {"bootID": ""},
            ),
            "runtime state bootID is missing",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "runtime-state.json",
                {"capabilities": {}},
            ),
            "runtime capability is not available",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "runtime-state.json",
                {"diskHealth": {"rootFilesystemReadOnly": True, "kernelErrors": []}},
            ),
            "root filesystem is not explicitly writable",
        ),
        (
            lambda context: update_json(
                context.runtime_dir / "runtime-state.json",
                {"vitalDBObservation": []},
            ),
            "vitalDBObservation must be object or null",
        ),
        (
            lambda context: update_runtime_service(
                context,
                "app",
                {"uptimeSeconds": None},
            ),
            "compose service uptime is invalid for runtime smoke",
        ),
        (
            lambda context: update_runtime_service(
                context,
                "app",
                {"uptimeSeconds": 41_126_400},
            ),
            "compose service uptime is invalid for runtime smoke",
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
            operations=fake_operations(inactive_service="tirosh-runtime-state.service"),
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


def test_runtime_boot_smoke_rejects_stale_request_file(tmp_path: Path) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)
    (context.runtime_dir / "redis-backup.request").write_text("{}", encoding="utf-8")

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(context=context, operations=fake_operations())

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert "stale guest command requests exist" in failed_stage_message(document)


def test_runtime_boot_smoke_rejects_failed_dev_testkit_service(tmp_path: Path) -> None:
    context = runtime_boot_context(tmp_path, dev_build=True)
    write_valid_runtime_documents(context, testkit_enabled=True)

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(
            context=context,
            operations=fake_operations(
                service_results={"tirosh-vitalserver-testkit.service": "failed"},
            ),
        )

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert "testkit service failed for dev build" in failed_stage_message(document)


def test_runtime_boot_smoke_accepts_inactive_successful_dev_testkit_oneshot(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(tmp_path, dev_build=True)
    write_valid_runtime_documents(context, testkit_enabled=True)

    run_runtime_boot_smoke(
        context=context,
        operations=fake_operations(
            inactive_service="tirosh-vitalserver-testkit.service",
        ),
    )

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["status"] == "passed"


@pytest.mark.parametrize("health", [None, "", "starting", "unhealthy"])
def test_runtime_boot_smoke_rejects_service_without_explicit_healthy_status(
    tmp_path: Path,
    health: object,
) -> None:
    context = runtime_boot_context(tmp_path)
    write_valid_runtime_documents(context)
    state_path = context.runtime_dir / "runtime-state.json"
    document = read_json(state_path)
    document["containerServices"][0]["health"] = health
    write_json(state_path, document)

    with pytest.raises(SystemExit):
        run_runtime_boot_smoke(context=context, operations=fake_operations())

    manifest = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert "compose services are not ready" in failed_stage_message(manifest)


def test_runtime_boot_smoke_waits_for_compose_service_to_become_healthy(
    tmp_path: Path,
) -> None:
    context = runtime_boot_context(tmp_path, compose_ready_timeout_seconds=10)
    write_valid_runtime_documents(context)
    state_path = context.runtime_dir / "runtime-state.json"
    document = read_json(state_path)
    document["containerServices"][0]["health"] = "starting"
    write_json(state_path, document)

    def mark_healthy(seconds: float) -> None:
        refreshed = read_json(state_path)
        refreshed["containerServices"][0]["health"] = "healthy"
        write_json(state_path, refreshed)

    run_runtime_boot_smoke(
        context=context,
        operations=fake_operations(sleep=mark_healthy),
    )

    manifest = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert manifest["status"] == "passed"
    assert stage_status(manifest, "compose-services") == "passed"


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
    assert context.dev_build is True
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
            lambda deploy_dir: update_json(
                deploy_dir / "runtime-config.json",
                {"testkitEnabled": None},
            ),
            "runtime config testkitEnabled must be an explicit boolean",
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
        max_runtime_state_age_seconds=180,
        compose_ready_timeout_seconds=compose_ready_timeout_seconds,
        dev_build=dev_build,
    )


def write_valid_runtime_documents(
    context: RuntimeBootSmokeContext,
    *,
    testkit_enabled: bool = False,
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
    services = [
        {
            "service": name,
            "exitCode": 0,
            "health": "healthy",
            "name": f"{name}-1",
            "startedAt": timestamp(NOW),
            "state": "running",
            "uptimeSeconds": 10,
        }
        for name in (
            "redis",
            "app",
            "audit-proxy",
            "vitaldb-observer",
            "redis-ui",
            "swagger-ui",
            "edge",
            *(("testkit",) if testkit_enabled else ()),
        )
    ]
    write_json(
        context.runtime_dir / "runtime-state.json",
        {
            "schemaVersion": 1,
            "bootID": "boot-test",
            "vmIP": "192.168.64.2",
            "updatedAt": timestamp(NOW),
            "probeErrors": [],
            "containerServices": services,
            "diskHealth": {
                "rootFilesystemReadOnly": False,
                "kernelErrors": [],
            },
            "capabilities": {
                "prepareUpdateShutdown": True,
                "activateUpdate": True,
                "redisBackup": True,
                "redisRestore": True,
                "repairDatastore": True,
            },
            "httpProbes": {
                "guestHTTP": {"status": "200"},
                "redisUIHTTP": {"status": "200"},
                "swaggerUIHTTP": {"status": "200"},
            },
            "vitalDBObservation": {},
        },
    )
    write_json(
        context.deploy_dir / "runtime-config.json",
        {
            "publicHost": "127.0.0.1",
            "publicPort": 18080,
            "testkitEnabled": testkit_enabled,
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
            "testkitEnabled": True,
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


def update_runtime_service(
    context: RuntimeBootSmokeContext,
    service_name: str,
    changes: dict[str, object],
) -> None:
    path = context.runtime_dir / "runtime-state.json"
    document = read_json(path)
    services = document["containerServices"]
    for service in services:
        if service["service"] == service_name:
            service.update(changes)
    write_json(path, document)


def fake_operations(
    *,
    inactive_service: str | None = None,
    service_results: dict[str, str] | None = None,
    http_status: Callable[[str, float], int] | None = None,
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
        now=lambda: NOW,
        sleep=sleep or (lambda seconds: None),
    )


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
