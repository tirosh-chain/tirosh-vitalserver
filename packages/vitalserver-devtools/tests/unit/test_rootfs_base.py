from __future__ import annotations

import json

import pytest

from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    require_stopped_lifecycle,
)


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
