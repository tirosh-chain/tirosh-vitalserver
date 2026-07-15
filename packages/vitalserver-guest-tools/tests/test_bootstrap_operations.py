from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from tirosh_guest_tools.application.bootstrap import GuestBootstrapContext
from tirosh_guest_tools.infrastructure import bootstrap_operations


def test_expand_root_filesystem_derives_nvme_partition_when_lsblk_partnum_is_empty(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    commands: list[list[str]] = []
    command_outputs = {
        ("findmnt", "-n", "-o", "SOURCE", "/"): "/dev/nvme1n1p1\n",
        ("lsblk", "-no", "PKNAME", "/dev/nvme1n1p1"): "nvme1n1\n",
        ("lsblk", "-no", "PARTNUM", "/dev/nvme1n1p1"): "",
        ("findmnt", "-n", "-o", "FSTYPE", "/"): "ext4\n",
    }

    def fake_run(
        arguments: list[str],
        *,
        check: bool = True,
        capture_output: bool = False,
        text: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(arguments)
        return subprocess.CompletedProcess(
            args=arguments,
            returncode=0,
            stdout=command_outputs.get(tuple(arguments), ""),
            stderr="",
        )

    monkeypatch.setattr(bootstrap_operations.subprocess, "run", fake_run)
    monkeypatch.setattr(
        bootstrap_operations.shutil,
        "which",
        lambda _: "/usr/bin/growpart",
    )

    bootstrap_operations.expand_root_filesystem()

    assert ["growpart", "/dev/nvme1n1", "1"] in commands
    assert ["resize2fs", "/dev/nvme1n1p1"] in commands
    assert ["df", "-h", "/"] in commands


def test_expand_root_filesystem_derives_nvme_parent_when_lsblk_parent_is_empty(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    commands: list[list[str]] = []
    command_outputs = {
        ("findmnt", "-n", "-o", "SOURCE", "/"): "/dev/nvme1n1p1\n",
        ("lsblk", "-no", "PKNAME", "/dev/nvme1n1p1"): "",
        ("lsblk", "-no", "PARTNUM", "/dev/nvme1n1p1"): "",
        ("findmnt", "-n", "-o", "FSTYPE", "/"): "ext4\n",
    }

    def fake_run(
        arguments: list[str],
        *,
        check: bool = True,
        capture_output: bool = False,
        text: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(arguments)
        return subprocess.CompletedProcess(
            args=arguments,
            returncode=0,
            stdout=command_outputs.get(tuple(arguments), ""),
            stderr="",
        )

    monkeypatch.setattr(bootstrap_operations.subprocess, "run", fake_run)
    monkeypatch.setattr(
        bootstrap_operations.shutil,
        "which",
        lambda _: "/usr/bin/growpart",
    )

    bootstrap_operations.expand_root_filesystem()

    assert ["growpart", "/dev/nvme1n1", "1"] in commands


def test_command_text_rejects_missing_required_output(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fake_run(
        arguments: list[str],
        *,
        check: bool = True,
        capture_output: bool = False,
        text: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(
            args=arguments,
            returncode=0,
            stdout="",
            stderr="",
        )

    monkeypatch.setattr(bootstrap_operations.subprocess, "run", fake_run)

    with pytest.raises(RuntimeError, match="command returned no output"):
        bootstrap_operations.command_text(["findmnt", "-n", "-o", "SOURCE", "/"])


def test_sync_clock_uses_explicit_host_time_contract(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = bootstrap_context(tmp_path)
    (context.deploy_dir / "host-time.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "epochSeconds": 1_781_273_647,
                "updatedAt": "2026-06-13T10:14:07Z",
            }
        ),
        encoding="utf-8",
    )
    commands: list[list[str]] = []
    monkeypatch.setattr(
        bootstrap_operations,
        "run",
        lambda command: commands.append(command),
    )

    bootstrap_operations.sync_clock(context)

    assert commands == [["date", "-u", "-s", "@1781273647"]]


def test_sync_host_time_mounts_runtime_share_before_reading_contract(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = bootstrap_context(tmp_path)
    (context.deploy_dir / "host-time.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "epochSeconds": 1_781_273_647,
                "updatedAt": "2026-06-13T10:14:07Z",
            }
        ),
        encoding="utf-8",
    )
    events: list[str] = []
    monkeypatch.setattr(
        bootstrap_operations,
        "default_bootstrap_context",
        lambda: context,
    )
    monkeypatch.setattr(
        bootstrap_operations,
        "mount_runtime_share",
        lambda: events.append("mount-runtime-share"),
    )
    monkeypatch.setattr(
        bootstrap_operations,
        "run",
        lambda command: events.append(" ".join(command)),
    )

    bootstrap_operations.sync_host_time()

    assert events == [
        "mount-runtime-share",
        "date -u -s @1781273647",
    ]


def test_sync_clock_rejects_missing_host_time_contract(tmp_path: Path) -> None:
    with pytest.raises(RuntimeError, match="host time contract is unreadable"):
        bootstrap_operations.sync_clock(bootstrap_context(tmp_path))


def test_prepare_shared_directories_creates_recorder_ingress_bind_sources(
    tmp_path: Path,
) -> None:
    context = bootstrap_context(tmp_path)

    bootstrap_operations.prepare_shared_directories(context)

    assert context.vital_files_mount.is_dir()
    assert (context.runtime_dir / "recorder-ingress-failures").is_dir()
    assert (context.runtime_dir / "recorder-ingress-raw").is_dir()
    assert (context.runtime_dir / "recorder-ingress-recovery").is_dir()
    assert (context.runtime_dir / "redis-relay-status").is_dir()
    assert (context.runtime_dir.parent / "vr-release").is_dir()


def test_load_bundled_docker_images_retries_one_failed_import(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = bootstrap_context(tmp_path)
    image_bundle = context.deploy_dir / "docker-images/vitalserver-images.tar.gz"
    image_bundle.parent.mkdir()
    image_bundle.write_bytes(b"bundle")
    commands: list[list[str]] = []

    def fake_run(arguments: list[str]) -> subprocess.CompletedProcess[str]:
        commands.append(arguments)
        if len(commands) == 1:
            raise subprocess.CalledProcessError(1, arguments)
        return subprocess.CompletedProcess(arguments, 0)

    monkeypatch.setattr(bootstrap_operations, "run", fake_run)
    monkeypatch.setattr(bootstrap_operations.time, "sleep", lambda _: None)

    bootstrap_operations.load_bundled_docker_images(context)

    assert commands == [
        ["docker", "load", "-i", str(image_bundle)],
        ["docker", "load", "-i", str(image_bundle)],
    ]


def test_load_bundled_docker_images_reports_failure_after_bounded_attempts(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = bootstrap_context(tmp_path)
    image_bundle = context.deploy_dir / "docker-images/vitalserver-images.tar.gz"
    image_bundle.parent.mkdir()
    image_bundle.write_bytes(b"bundle")
    commands: list[list[str]] = []

    def failed_run(arguments: list[str]) -> subprocess.CompletedProcess[str]:
        commands.append(arguments)
        raise subprocess.CalledProcessError(1, arguments)

    monkeypatch.setattr(bootstrap_operations, "run", failed_run)
    monkeypatch.setattr(bootstrap_operations.time, "sleep", lambda _: None)

    with pytest.raises(subprocess.CalledProcessError):
        bootstrap_operations.load_bundled_docker_images(context)

    assert len(commands) == bootstrap_operations.DOCKER_IMAGE_LOAD_MAX_ATTEMPTS


def bootstrap_context(tmp_path: Path) -> GuestBootstrapContext:
    deploy_dir = tmp_path / "deploy"
    deploy_dir.mkdir(parents=True)
    return GuestBootstrapContext(
        deploy_dir=deploy_dir,
        runtime_dir=tmp_path / "run",
        vital_files_mount=tmp_path / "vital-files",
        bootstrap_result=tmp_path / "run/bootstrap-result.json",
    )
