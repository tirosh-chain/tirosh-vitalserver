from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.guest_image import ubuntu


def test_validate_qcow2_image_rejects_unexpected_image_format(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    image = tmp_path / "ubuntu.img"
    image.write_bytes(b"image")
    monkeypatch.setattr(
        ubuntu,
        "capture_json",
        lambda command: {"format": "raw", "virtual-size": 1024},
    )

    with pytest.raises(SystemExit, match="expected qcow2 image"):
        ubuntu.validate_qcow2_image(image, label="Ubuntu cloud image")


def test_validate_qcow2_image_rejects_qemu_check_failure(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    image = tmp_path / "ubuntu.img"
    image.write_bytes(b"image")
    monkeypatch.setattr(
        ubuntu,
        "capture_json",
        lambda command: {"format": "qcow2", "virtual-size": 1024},
    )

    def fail_run(command):
        raise subprocess.CalledProcessError(returncode=1, cmd=command)

    monkeypatch.setattr(ubuntu, "run", fail_run)

    with pytest.raises(SystemExit, match="qemu-img check failed"):
        ubuntu.validate_qcow2_image(image, label="Ubuntu cloud image")


def test_validate_raw_disk_image_rejects_undersized_disk(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    disk = tmp_path / "vm-disk.img"
    disk.write_bytes(b"disk")
    monkeypatch.setattr(
        ubuntu,
        "capture_json",
        lambda command: {"format": "raw", "virtual-size": 1024},
    )

    with pytest.raises(SystemExit, match="expected>=2048"):
        ubuntu.validate_raw_disk_image(disk, min_virtual_size=2048)
