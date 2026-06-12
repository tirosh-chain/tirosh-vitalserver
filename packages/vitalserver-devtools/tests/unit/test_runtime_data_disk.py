from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.guest_image import runtime_data_disk
from tirosh_vitalserver.devtools.core.guest_image import RuntimeDataDiskPlan


def test_prepare_ephemeral_runtime_data_disk_recreates_stale_raw_disk(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    plan = runtime_data_disk_plan(tmp_path, disk_size="16G")
    plan.disk_image.parent.mkdir(parents=True)
    plan.disk_image.write_text("stale", encoding="utf-8")
    commands: list[list[str]] = []

    monkeypatch.setattr(runtime_data_disk, "require_tool", lambda *_args: None)

    def run(command: list[str]) -> None:
        commands.append(command)
        plan.disk_image.write_bytes(b"")

    monkeypatch.setattr(runtime_data_disk, "run", run)
    monkeypatch.setattr(
        runtime_data_disk,
        "qemu_image_info",
        lambda _path, *, label: {
            "format": "raw",
            "virtual-size": 16 * 1024 * 1024 * 1024,
        },
    )

    result = runtime_data_disk.prepare_ephemeral_runtime_data_disk(plan)

    assert commands == [[
        "qemu-img",
        "create",
        "-f",
        "raw",
        str(plan.disk_image),
        "16G",
    ]]
    assert result["path"] == str(plan.disk_image)
    assert result["diskImageName"] == "runtime-data.img"
    assert result["filesystemLabel"] == "vital-runtime"
    assert result["mountPath"] == "/mnt/runtime"
    assert result["dockerDataRoot"] == "/mnt/runtime/docker"
    assert result["containerdRoot"] == "/mnt/runtime/containerd"
    assert result["removedStaleDisk"] is True


def test_prepare_ephemeral_runtime_data_disk_rejects_size_mismatch(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    plan = runtime_data_disk_plan(tmp_path, disk_size="16G")
    monkeypatch.setattr(runtime_data_disk, "require_tool", lambda *_args: None)
    monkeypatch.setattr(runtime_data_disk, "run", lambda _command: None)
    monkeypatch.setattr(
        runtime_data_disk,
        "qemu_image_info",
        lambda _path, *, label: {
            "format": "raw",
            "virtual-size": 8 * 1024 * 1024 * 1024,
        },
    )

    with pytest.raises(SystemExit, match="invalid runtime data disk size"):
        runtime_data_disk.prepare_ephemeral_runtime_data_disk(plan)


def runtime_data_disk_plan(tmp_path: Path, *, disk_size: str) -> RuntimeDataDiskPlan:
    return RuntimeDataDiskPlan(
        config_path=tmp_path / "config/vm-build.toml",
        vm_home=tmp_path / "vm",
        runtime_dir=tmp_path / "vm/runtime",
        disk_image=tmp_path / "vm/runtime/runtime-data.img",
        disk_image_name="runtime-data.img",
        disk_size=disk_size,
        filesystem_label="vital-runtime",
        mount_path="/mnt/runtime",
        docker_data_root="/mnt/runtime/docker",
        containerd_root="/mnt/runtime/containerd",
    )
