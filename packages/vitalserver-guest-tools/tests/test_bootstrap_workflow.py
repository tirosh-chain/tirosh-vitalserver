from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_guest_tools.application.bootstrap import (
    BootstrapResultDocument,
    DockerSmokeResult,
    EdgeReadinessProbeResult,
    GuestBootstrapContext,
    GuestBootstrapOperations,
    GuestBootstrapWorkflow,
    run_guest_bootstrap,
)


def test_guest_bootstrap_workflow_orders_runtime_data_before_docker_consumers(
    tmp_path: Path,
) -> None:
    context = bootstrap_context(tmp_path)
    events: list[str] = []

    run_guest_bootstrap(context=context, operations=fake_operations(events))

    assert_before(events, "mount-shares", "sync-clock")
    assert_before(events, "sync-clock", "result:running")
    assert_before(events, "prepare-runtime-data", "start-docker")
    assert_before(
        events,
        "start-docker",
        "start-guest-background-services",
    )
    assert_before(
        events,
        "start-compose",
        "start-container-logs",
    )
    result = json.loads(context.bootstrap_result.read_text(encoding="utf-8"))
    assert result["status"] == "completed"


def test_guest_bootstrap_rejects_docker_start_before_runtime_data(
    tmp_path: Path,
) -> None:
    workflow = GuestBootstrapWorkflow(
        context=bootstrap_context(tmp_path),
        operations=fake_operations([]),
    )

    with pytest.raises(
        RuntimeError,
        match="start-docker requires prepare-runtime-data",
    ):
        workflow.start_docker()


def test_guest_bootstrap_rejects_container_logs_before_compose(
    tmp_path: Path,
) -> None:
    workflow = GuestBootstrapWorkflow(
        context=bootstrap_context(tmp_path),
        operations=fake_operations([]),
    )

    with pytest.raises(
        RuntimeError,
        match="start-container-logs requires start-compose",
    ):
        workflow.start_container_logs()


def test_guest_bootstrap_cli_is_registered() -> None:
    pyproject = Path(__file__).parents[1] / "pyproject.toml"
    assert "tirosh-vitalserver-bootstrap" in pyproject.read_text(encoding="utf-8")


def bootstrap_context(tmp_path: Path) -> GuestBootstrapContext:
    deploy_dir = tmp_path / "deploy"
    runtime_dir = tmp_path / "run"
    (deploy_dir / "docker-images").mkdir(parents=True)
    (deploy_dir / "docker-images" / "vitalserver-images.tar.gz").write_bytes(b"image")
    (deploy_dir / "compose.yaml").write_text("services: {}\n", encoding="utf-8")
    (deploy_dir / "runtime-config.json").write_text("{}\n", encoding="utf-8")
    metadata = deploy_dir / "build-metadata" / "rootfs-input.json"
    metadata.parent.mkdir(parents=True)
    metadata.write_text(
        json.dumps({"runtimeBootSmoke": {"enabled": False}}),
        encoding="utf-8",
    )
    return GuestBootstrapContext(
        deploy_dir=deploy_dir,
        runtime_dir=runtime_dir,
        vital_files_mount=tmp_path / "vital-files",
        bootstrap_result=runtime_dir / "bootstrap-result.json",
        edge_ready_timeout_seconds=0.1,
        edge_ready_poll_seconds=0.0,
    )


def fake_operations(events: list[str]) -> GuestBootstrapOperations:
    def write_result(path: Path, document: BootstrapResultDocument) -> None:
        events.append(f"result:{document.status}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                {
                    "bootID": document.boot_id,
                    "message": document.message,
                    "operation": document.operation,
                    "reasonCodes": list(document.reason_codes),
                    "schemaVersion": document.schema_version,
                    "status": document.status,
                    "updatedAt": document.updated_at,
                }
            ),
            encoding="utf-8",
        )

    return GuestBootstrapOperations(
        current_time_seconds=lambda: 0.0,
        sleep=lambda _: events.append("sleep"),
        now=lambda: "2026-06-13T00:00:00Z",
        boot_id=lambda: "test-boot-id",
        mount_shares=lambda: events.append("mount-shares"),
        sync_clock=lambda _: events.append("sync-clock"),
        write_bootstrap_result=write_result,
        missing_deploy_bundle_files=lambda _: [],
        expand_root_filesystem=lambda: events.append("expand-root-filesystem"),
        missing_runtime_packages=lambda: [],
        install_runtime_files=lambda _: events.append("install-runtime-files"),
        prepare_runtime_data=lambda: events.append("prepare-runtime-data"),
        write_initial_runtime_state=lambda: events.append("write-runtime-state"),
        start_docker=lambda: events.append("start-docker"),
        start_avahi=lambda: events.append("start-avahi"),
        start_guest_background_services=lambda: events.append(
            "start-guest-background-services"
        ),
        prepare_shared_directories=lambda _: events.append(
            "prepare-shared-directories"
        ),
        load_bundled_docker_images=lambda _: events.append("load-docker-images"),
        run_docker_runtime_smoke=lambda _: DockerSmokeResult(passed=True),
        cleanup_docker_cache=lambda: events.append("cleanup-docker-cache"),
        build_missing_images=lambda: events.append("build-missing-images"),
        start_compose=lambda: events.append("start-compose"),
        start_container_logs=lambda: events.append("start-container-logs"),
        probe_edge_readiness=lambda _url, _timeout: EdgeReadinessProbeResult(
            status_code=200
        ),
        write_runtime_state_once=lambda: events.append("write-runtime-state"),
        write_edge_diagnostics=lambda: events.append("write-edge-diagnostics"),
        restart_runtime_state=lambda: events.append("restart-runtime-state"),
        start_optional_testkit=lambda: events.append("start-optional-testkit"),
        runtime_boot_smoke_enabled=lambda _: False,
        run_runtime_boot_smoke=lambda: events.append("run-runtime-boot-smoke"),
    )


def assert_before(events: list[str], first: str, second: str) -> None:
    assert first in events
    assert second in events
    assert events.index(first) < events.index(second)
