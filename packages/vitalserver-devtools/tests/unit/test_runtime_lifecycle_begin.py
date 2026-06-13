from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import runtime_lifecycle
from tirosh_vitalserver.devtools.application.inputs import (
    GoldenRootfsPreflightInput,
    RootfsRunInput,
)


def test_begin_golden_rootfs_run_records_runtime_data_disk_contract(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_build_config(tmp_path / "config/vm-build.toml")
    vm_home = tmp_path / "vm"
    stale_ready = vm_home / "data/run/rootfs-ready"
    stale_ready.parent.mkdir(parents=True)
    stale_ready.write_text("stale", encoding="utf-8")
    vm_config = vm_home / "runtime/vm-config.json"
    vm_config.parent.mkdir(parents=True)
    vm_config.write_text(
        json.dumps({"kernelPath": "/runtime/Image"}),
        encoding="utf-8",
    )

    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "prepare_ephemeral_runtime_data_disk",
        lambda plan: {
            "path": str(plan.disk_image),
            "diskImageName": plan.disk_image_name,
            "diskSize": plan.disk_size,
            "filesystemLabel": plan.filesystem_label,
            "mountPath": plan.mount_path,
            "dockerDataRoot": plan.docker_data_root,
            "containerdRoot": plan.containerd_root,
            "removedStaleDisk": False,
        },
    )

    result = runtime_lifecycle.begin_golden_rootfs_run(
        RootfsRunInput(
            config=Path("config/vm-build.toml"),
            vm_home=Path("vm"),
            run_id="run-test",
        )
    )

    assert result == 0
    assert not stale_ready.exists()
    context = json.loads(
        (vm_home / "run/golden-rootfs-run.json").read_text(encoding="utf-8")
    )
    assert context["runId"] == "run-test"
    assert context["removedStaleProof"] == [str(stale_ready)]
    assert context["runtimeDataDisk"] == {
        "path": str(vm_home / "runtime/runtime-data.img"),
        "diskImageName": "runtime-data.img",
        "diskSize": "16G",
        "filesystemLabel": "vital-runtime",
        "mountPath": "/mnt/runtime",
        "dockerDataRoot": "/mnt/runtime/docker",
        "containerdRoot": "/mnt/runtime/containerd",
        "removedStaleDisk": False,
    }
    updated_vm_config = json.loads(vm_config.read_text(encoding="utf-8"))
    assert updated_vm_config["runtimeDataDiskPath"] == str(
        vm_home / "runtime/runtime-data.img"
    )


def test_begin_golden_rootfs_run_requires_initialized_vm_config(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_build_config(tmp_path / "config/vm-build.toml")
    stale_ready = tmp_path / "vm/data/run/rootfs-ready"
    stale_ready.parent.mkdir(parents=True)
    stale_ready.write_text("stale", encoding="utf-8")
    prepared = False
    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)

    def prepare(plan):
        nonlocal prepared
        prepared = True
        return {
            "path": str(plan.disk_image),
            "diskImageName": plan.disk_image_name,
            "diskSize": plan.disk_size,
            "filesystemLabel": plan.filesystem_label,
            "mountPath": plan.mount_path,
            "dockerDataRoot": plan.docker_data_root,
            "containerdRoot": plan.containerd_root,
            "removedStaleDisk": False,
        }

    monkeypatch.setattr(
        runtime_lifecycle,
        "prepare_ephemeral_runtime_data_disk",
        prepare,
    )

    with pytest.raises(SystemExit, match="VM config is missing"):
        runtime_lifecycle.begin_golden_rootfs_run(
            RootfsRunInput(
                config=Path("config/vm-build.toml"),
                vm_home=Path("vm"),
                run_id="run-test",
            )
        )
    assert prepared is False
    assert stale_ready.read_text(encoding="utf-8") == "stale"


def test_golden_rootfs_preflight_rejects_unavailable_apt_snapshot(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_rootfs_input(vm_home, run_id="run-test")
    write_run_context(vm_home, run_id="run-test")
    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )
    monkeypatch.setattr(
        runtime_lifecycle,
        "check_apt_snapshot_available",
        lambda snapshot: [
            runtime_lifecycle.PreflightCheck(
                name="apt-snapshot",
                status=runtime_lifecycle.PreflightStatus.UNAVAILABLE,
                message="Ubuntu apt snapshot endpoint is unavailable",
                detail=f"snapshot={snapshot} status=503",
            )
        ],
    )

    with pytest.raises(SystemExit):
        runtime_lifecycle.preflight_golden_rootfs(
            GoldenRootfsPreflightInput(
                config=Path("config/vm-build.toml"),
                vm_home=Path("vm"),
                expected_run_id="run-test",
            )
        )


def test_golden_rootfs_preflight_rejects_invalid_rootfs_metadata(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_run_context(vm_home, run_id="run-test")
    metadata = vm_home / "data/deploy/build-metadata/rootfs-input.json"
    metadata.parent.mkdir(parents=True)
    metadata.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": "run-test",
                "guestClockUtc": "2026-06-13T02:00:00Z",
                "ubuntu": {"aptSnapshot": ""},
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )

    report = runtime_lifecycle.golden_rootfs_preflight_report(
        vm_home=vm_home,
        expected_run_id="run-test",
    )

    assert not report.passed
    assert any(
        check.status == runtime_lifecycle.PreflightStatus.INVALID
        and check.name == "rootfs-input-metadata"
        for check in report.blockers
    )


def test_golden_rootfs_preflight_rejects_stale_proof_before_vm_start(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_rootfs_input(vm_home, run_id="run-test")
    write_run_context(vm_home, run_id="run-test")
    ready = vm_home / "data/run/rootfs-ready"
    ready.parent.mkdir(parents=True)
    ready.write_text(json.dumps({"runId": "old-run"}), encoding="utf-8")
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )
    monkeypatch.setattr(runtime_lifecycle, "check_apt_snapshot_available", lambda _: [])

    report = runtime_lifecycle.golden_rootfs_preflight_report(
        vm_home=vm_home,
        expected_run_id="run-test",
    )

    assert not report.passed
    assert any(check.name == "rootfs-ready" for check in report.blockers)


def test_golden_rootfs_preflight_accepts_explicit_inputs(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_rootfs_input(vm_home, run_id="run-test")
    write_run_context(vm_home, run_id="run-test")
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )
    monkeypatch.setattr(
        runtime_lifecycle,
        "check_apt_snapshot_available",
        lambda _: [
            runtime_lifecycle.PreflightCheck(
                name="apt-snapshot",
                status=runtime_lifecycle.PreflightStatus.PASSED,
                message="snapshot ok",
            )
        ],
    )

    report = runtime_lifecycle.golden_rootfs_preflight_report(
        vm_home=vm_home,
        expected_run_id="run-test",
    )

    assert report.passed


def write_build_config(path: Path) -> None:
    path.parent.mkdir(parents=True)
    path.write_text(
        """
[guest.runtime]
runtime_dir = "runtime"
rootfs_size = "8G"
disk_image_name = "vm-disk.img"

[guest.runtime_data]
disk_image_name = "runtime-data.img"
disk_size = "16G"
filesystem_label = "vital-runtime"
mount_path = "/mnt/runtime"
docker_data_root = "/mnt/runtime/docker"
containerd_root = "/mnt/runtime/containerd"
""".lstrip(),
        encoding="utf-8",
    )


def write_run_context(vm_home: Path, *, run_id: str) -> None:
    path = vm_home / "run/golden-rootfs-run.json"
    path.parent.mkdir(parents=True)
    path.write_text(
        json.dumps({"schemaVersion": 1, "runId": run_id}),
        encoding="utf-8",
    )


def write_rootfs_input(vm_home: Path, *, run_id: str) -> None:
    path = vm_home / "data/deploy/build-metadata/rootfs-input.json"
    path.parent.mkdir(parents=True)
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": run_id,
                "guestClockUtc": "2026-06-13T02:00:00Z",
                "ubuntu": {
                    "aptSnapshot": "20250515T000000Z",
                    "baseUrl": "https://cloud-images.ubuntu.com/releases/noble",
                },
            }
        ),
        encoding="utf-8",
    )
