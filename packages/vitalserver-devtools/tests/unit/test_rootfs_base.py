from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    require_runtime_manifest,
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


def test_require_runtime_manifest_accepts_passed_docker_smoke(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, status="passed", message="docker runtime smoke passed")

    require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_manifest(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)

    with pytest.raises(SystemExit, match="runtime manifest is missing"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_failed_docker_smoke(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, status="failed", message="runc EOF")

    with pytest.raises(SystemExit, match="Docker runtime smoke did not pass"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_compose_smoke(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(
        source,
        status="passed",
        message="docker runtime smoke passed",
        compose_status=None,
    )

    with pytest.raises(SystemExit, match="missing composeSmoke result"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_failed_compose_smoke(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(
        source,
        status="passed",
        message="docker runtime smoke passed",
        compose_status="failed",
        compose_message="edge did not become ready",
    )

    with pytest.raises(SystemExit, match="Compose runtime smoke did not pass"):
        require_runtime_manifest(source)


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
    write_runtime_manifest(source, status="passed", message="docker runtime smoke passed")

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


def rootfs_source_with_lifecycle(tmp_path: Path) -> Path:
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    lifecycle = tmp_path / "vm" / "run" / "vm-lifecycle.json"
    source.parent.mkdir(parents=True)
    lifecycle.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    lifecycle.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")
    return source


def write_runtime_manifest(
    source: Path,
    *,
    status: str,
    message: str,
    compose_status: str | None = "passed",
    compose_message: str = "compose runtime smoke passed",
) -> None:
    manifest = source.parent.parent / "data" / "run" / "rootfs-runtime-manifest.json"
    manifest.parent.mkdir(parents=True)
    document = {
        "schemaVersion": 1,
        "dockerSmoke": {
            "image": "redis:3.2.12-alpine",
            "status": status,
            "message": message,
        },
    }
    if compose_status is not None:
        document["composeSmoke"] = {
            "project": "vitalserver-rootfs-smoke",
            "status": compose_status,
            "message": compose_message,
        }
    manifest.write_text(
        json.dumps(document),
        encoding="utf-8",
    )
