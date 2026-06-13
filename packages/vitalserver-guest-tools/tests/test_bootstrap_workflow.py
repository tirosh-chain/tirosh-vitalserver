from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from tirosh_guest_tools.application.bootstrap import (
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

    assert_before(events, "prepare-runtime-data", "run:systemctl enable --now docker")
    assert_before(
        events,
        "run:systemctl enable --now docker",
        "run:systemctl start tirosh-vitalserver-command-poller.service",
    )
    assert_before(
        events,
        "run:systemctl start tirosh-vitalserver-compose.service",
        "run:systemctl start tirosh-vitalserver-container-logs.service",
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
    def run(
        arguments: list[str],
        *,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        events.append("run:" + " ".join(arguments))
        return subprocess.CompletedProcess(arguments, 0, "", "")

    def output(arguments: list[str]) -> str:
        events.append("output:" + " ".join(arguments))
        if arguments == ["findmnt", "-n", "-o", "SOURCE", "/"]:
            return "/dev/nvme0n1p1\n"
        if arguments == ["lsblk", "-no", "PKNAME", "/dev/nvme0n1p1"]:
            return "nvme0n1\n"
        if arguments == ["lsblk", "-no", "PARTNUM", "/dev/nvme0n1p1"]:
            return "1\n"
        if arguments == ["findmnt", "-n", "-o", "FSTYPE", "/"]:
            return "ext4\n"
        return ""

    def http_status(url: str, timeout_seconds: float) -> int:
        events.append(f"http:{url}")
        return 200

    return GuestBootstrapOperations(
        run=run,
        output=output,
        http_status=http_status,
        sleep=lambda _: events.append("sleep"),
        now=lambda: "2026-06-13T00:00:00Z",
        boot_id=lambda: "test-boot-id",
        mount_runtime_share=lambda: events.append("mount-runtime-share"),
        mount_vital_files_share=lambda: events.append("mount-vital-files-share"),
        install_guest_tools_runtime=lambda: events.append("install-guest-tools"),
        prepare_runtime_data=lambda: events.append("prepare-runtime-data"),
    )


def assert_before(events: list[str], first: str, second: str) -> None:
    assert first in events
    assert second in events
    assert events.index(first) < events.index(second)
