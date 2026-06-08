from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    require_stopped_lifecycle,
    run_rootfs_base,
)
from tirosh_vitalserver.devtools.adapters.toolchain.gzip_compression import (
    validate_gzip_file,
)
from tirosh_vitalserver.devtools.application.inputs import RootfsBaseInput


def test_require_stopped_lifecycle_accepts_stopped_vm(tmp_path):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    lifecycle = tmp_path / "vm" / "run" / "vm-lifecycle.json"
    source.parent.mkdir(parents=True)
    lifecycle.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    lifecycle.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")

    require_stopped_lifecycle(source)


def test_require_stopped_lifecycle_rejects_stopping_vm(tmp_path):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    lifecycle = tmp_path / "vm" / "run" / "vm-lifecycle.json"
    source.parent.mkdir(parents=True)
    lifecycle.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    lifecycle.write_text(json.dumps({"state": "stopping"}), encoding="utf-8")

    with pytest.raises(SystemExit, match="lifecycle is not stopped"):
        require_stopped_lifecycle(source)


def test_require_stopped_lifecycle_rejects_terminal_failure_reason(tmp_path):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    lifecycle = tmp_path / "vm" / "run" / "vm-lifecycle.json"
    source.parent.mkdir(parents=True)
    lifecycle.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    lifecycle.write_text(
        json.dumps({"state": "stopped", "terminalReason": "guest-kernel-panic"}),
        encoding="utf-8",
    )

    with pytest.raises(SystemExit, match="terminal failure reason"):
        require_stopped_lifecycle(source)


def test_validate_gzip_file_rejects_corrupt_output(tmp_path):
    output = tmp_path / "rootfs-base.raw.gz"
    output.write_bytes(b"not a gzip")

    with pytest.raises(SystemExit, match="gzip validation failed"):
        validate_gzip_file(output, expected_uncompressed_size=4)


def test_run_rootfs_base_rejects_corrupt_compressor_output(tmp_path, monkeypatch):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    output = tmp_path / "rootfs-base.raw.gz"
    lifecycle = tmp_path / "vm" / "run" / "vm-lifecycle.json"
    source.parent.mkdir(parents=True)
    lifecycle.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    lifecycle.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")

    def write_corrupt_gzip(source: Path, output: Path, *, threads: int) -> None:
        output.write_bytes(b"not a gzip")

    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base.gzip_file",
        write_corrupt_gzip,
    )

    with pytest.raises(SystemExit, match="gzip validation failed"):
        run_rootfs_base(RootfsBaseInput(
            source=source,
            output=output,
            force=True,
            compression_threads=1,
        ))
