from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    require_ready_marker,
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


def test_require_runtime_manifest_accepts_passed_rootfs_smoke(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source)

    require_runtime_manifest(source)


def test_require_ready_marker_accepts_matching_run_id(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_ready_marker(source, run_id="run-test")

    require_ready_marker(source, expected_run_id="run-test")


def test_require_ready_marker_rejects_stale_run_id(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_ready_marker(source, run_id="old-run")

    with pytest.raises(SystemExit, match="runId does not match"):
        require_ready_marker(source, expected_run_id="run-test")


def test_require_runtime_manifest_rejects_stale_run_id(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, run_id="old-run")

    with pytest.raises(SystemExit, match="runId does not match"):
        require_runtime_manifest(source, expected_run_id="run-test")


def test_require_runtime_manifest_rejects_missing_manifest(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)

    with pytest.raises(SystemExit, match="runtime manifest is missing"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_unsupported_schema(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, schema_version=1)

    with pytest.raises(SystemExit, match="schema is unsupported"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_kernel(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, kernel="")

    with pytest.raises(SystemExit, match="missing explicit Ubuntu input"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_input_metadata(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, metadata_status="missing")

    with pytest.raises(SystemExit, match="missing explicit Ubuntu input"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_empty_cache_key(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, cache_key="")

    with pytest.raises(SystemExit, match="missing explicit Ubuntu input"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_apt_snapshot(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, apt_snapshot="")

    with pytest.raises(SystemExit, match="missing explicit Ubuntu input"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_apt_plan(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, apt=None)

    with pytest.raises(SystemExit, match="missing apt plan proof"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_blocked_apt_plan(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(
        source,
        apt={
            "schemaVersion": 1,
            "runId": "run-test",
            "status": "blocked",
            "snapshot": "20250313T000000Z",
            "blockedUpgrades": ["python3"],
        },
    )

    with pytest.raises(SystemExit, match="apt plan is not allowed"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_apt_plan_snapshot_mismatch(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(
        source,
        apt={
            "schemaVersion": 1,
            "runId": "run-test",
            "status": "allowed",
            "snapshot": "20260518T000000Z",
            "blockedUpgrades": [],
        },
    )

    with pytest.raises(SystemExit, match="apt plan snapshot does not match"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_apt_plan_run_id_mismatch(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(
        source,
        apt={
            "schemaVersion": 1,
            "runId": "old-run",
            "status": "allowed",
            "snapshot": "20250313T000000Z",
            "blockedUpgrades": [],
        },
    )

    with pytest.raises(SystemExit, match="apt plan runId does not match"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_failed_docker_stage(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(
        source,
        stage_statuses={"docker-smoke": ("failed", "runc EOF")},
    )

    with pytest.raises(SystemExit, match="docker-smoke stage did not pass"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_compose_stage(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, omitted_stages={"compose-up"})

    with pytest.raises(SystemExit, match="missing compose-up stage"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_disk_space_stage(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, omitted_stages={"disk-space"})

    with pytest.raises(SystemExit, match="missing disk-space stage"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_failed_edge_ready_stage(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(
        source,
        stage_statuses={"edge-ready": ("timeout", "edge did not become ready")},
    )

    with pytest.raises(SystemExit, match="edge-ready stage did not pass"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_failed_cleanup(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, cleanup_status="cleanup-failed")

    with pytest.raises(SystemExit, match="cleanup did not pass"):
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
    write_runtime_manifest(source)
    write_ready_marker(source)

    def write_corrupt_gzip(source: Path, output: Path, *, threads: int) -> None:
        output.write_bytes(b"not a gzip")

    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )
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
            expected_run_id="run-test",
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
    schema_version: int = 2,
    run_id: str = "run-test",
    metadata_status: str = "loaded",
    base_url: str = "https://example.invalid/release",
    cache_key: str = "release-abcd",
    apt_snapshot: str = "20250313T000000Z",
    kernel: str = "6.8.0-test",
    stage_statuses: dict[str, tuple[str, str]] | None = None,
    omitted_stages: set[str] | None = None,
    cleanup_status: str = "passed",
    apt: dict[str, object] | None | bool = True,
) -> None:
    manifest = source.parent.parent / "data" / "run" / "rootfs-runtime-manifest.json"
    manifest.parent.mkdir(parents=True)
    stage_statuses = stage_statuses or {}
    omitted_stages = omitted_stages or set()
    stages = []
    for name in (
        "docker-service",
        "runtime-version",
        "docker-image-load",
        "docker-smoke",
        "disk-space",
        "compose-build",
        "compose-up",
        "edge-ready",
    ):
        if name in omitted_stages:
            continue
        status, message = stage_statuses.get(name, ("passed", f"{name} passed"))
        stages.append({
            "name": name,
            "status": status,
            "startedAt": "2026-06-11T00:00:00Z",
            "completedAt": "2026-06-11T00:00:01Z",
            "message": message,
            "details": {},
        })
    document = {
        "schemaVersion": schema_version,
        "runId": run_id,
        "ubuntu": {
            "metadataStatus": metadata_status,
            "aptSnapshot": apt_snapshot,
            "baseUrl": base_url,
            "cacheKey": cache_key,
            "kernel": kernel,
        },
        "runtime": {
            "docker": "Docker version test",
            "containerd": "containerd test",
            "runc": "runc test",
            "compose": "Docker Compose test",
        },
        "stages": stages,
        "cleanup": {
            "status": cleanup_status,
            "message": "cleanup message",
        },
        "diagnostics": {
            "path": "/mnt/tirosh/run/rootfs-smoke-diagnostics",
        },
    }
    if apt is True:
        document["apt"] = {
            "schemaVersion": 1,
            "runId": run_id,
            "status": "allowed",
            "snapshot": apt_snapshot,
            "blockedUpgrades": [],
            "installPackages": ["docker.io", "python3-venv"],
            "newPackages": ["docker.io"],
            "upgradedPackages": [],
            "removedPackages": [],
        }
    elif isinstance(apt, dict):
        document["apt"] = apt
    manifest.write_text(
        json.dumps(document),
        encoding="utf-8",
    )


def write_ready_marker(source: Path, *, run_id: str = "run-test") -> None:
    marker = source.parent.parent / "data" / "run" / "rootfs-ready"
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": run_id,
                "readyAt": "2026-06-11T00:00:02Z",
            }
        ),
        encoding="utf-8",
    )
