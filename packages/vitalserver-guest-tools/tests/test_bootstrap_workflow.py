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
    assert_before(events, "prepare-runtime-data", "migrate-control-store")
    assert_before(
        events,
        "migrate-control-store",
        "provision-initial-update-owners",
    )
    assert_before(events, "provision-initial-update-owners", "start-docker")
    assert_before(
        events,
        "start-docker",
        "start-guest-background-services",
    )
    assert_before(
        events,
        "start-compose",
        "write-runtime-observation",
    )
    assert_before(
        events,
        "write-runtime-observation",
        "start-container-logs",
    )
    assert "build-missing-images" not in events
    result = json.loads(context.bootstrap_result.read_text(encoding="utf-8"))
    assert result["status"] == "completed"


def test_guest_bootstrap_reports_each_running_step_and_failed_step(
    tmp_path: Path,
) -> None:
    context = bootstrap_context(tmp_path)
    events: list[str] = []
    operations = fake_operations(events)
    operations = GuestBootstrapOperations(
        **{
            **operations.__dict__,
            "prepare_runtime_data": lambda: (_ for _ in ()).throw(
                RuntimeError("stop failed")
            ),
        }
    )

    with pytest.raises(RuntimeError, match="stop failed"):
        run_guest_bootstrap(context=context, operations=operations)

    running_messages = [
        event.removeprefix("result:running:")
        for event in events
        if event.startswith("result:running:")
    ]
    assert "Guest bootstrap is running." in running_messages
    assert "Guest bootstrap step running: prepare-runtime-data." in running_messages
    result = json.loads(context.bootstrap_result.read_text(encoding="utf-8"))
    assert result["status"] == "failed"
    assert result["message"] == (
        "Guest bootstrap failed at step: prepare-runtime-data."
    )


def test_guest_bootstrap_rejects_docker_start_before_owner_provisioning(
    tmp_path: Path,
) -> None:
    workflow = GuestBootstrapWorkflow(
        context=bootstrap_context(tmp_path),
        operations=fake_operations([]),
    )

    with pytest.raises(
        RuntimeError,
        match="start-docker requires provision-initial-update-owners",
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


def test_guest_bootstrap_rejects_initial_observation_before_compose(
    tmp_path: Path,
) -> None:
    workflow = GuestBootstrapWorkflow(
        context=bootstrap_context(tmp_path),
        operations=fake_operations([]),
    )

    with pytest.raises(
        RuntimeError,
        match="write-initial-runtime-observation requires start-compose",
    ):
        workflow.write_initial_runtime_observation()


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
        events.append(f"result:{document.status}:{document.message}")
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
        migrate_control_store=lambda: events.append("migrate-control-store"),
        provision_initial_update_owners=lambda _: events.append(
            "provision-initial-update-owners"
        ),
        write_initial_runtime_observation=lambda: events.append(
            "write-runtime-observation"
        ),
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
        start_compose=lambda: events.append("start-compose"),
        start_container_logs=lambda: events.append("start-container-logs"),
        probe_edge_readiness=lambda _url, _timeout: EdgeReadinessProbeResult(
            status_code=200
        ),
        write_runtime_observation_once=lambda: events.append(
            "write-runtime-observation"
        ),
        write_edge_diagnostics=lambda: events.append("write-edge-diagnostics"),
        restart_runtime_observation=lambda: events.append(
            "restart-runtime-observation"
        ),
        runtime_boot_smoke_enabled=lambda _: False,
        run_runtime_boot_smoke=lambda: events.append("run-runtime-boot-smoke"),
    )


def assert_before(events: list[str], first: str, second: str) -> None:
    first_index = next(
        index for index, event in enumerate(events) if event.startswith(first)
    )
    second_index = next(
        index for index, event in enumerate(events) if event.startswith(second)
    )
    assert first_index < second_index
