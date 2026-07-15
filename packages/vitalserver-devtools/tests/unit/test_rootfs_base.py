from __future__ import annotations

import gzip
import hashlib
import json
import sqlite3
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION,
    require_ready_marker,
    require_rootfs_artifact_guest_deploy_match,
    require_rootfs_artifact_manifest,
    require_runtime_manifest,
    require_stopped_lifecycle,
    rootfs_artifact_manifest_path,
    run_rootfs_base,
)
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    GUEST_DEPLOY_MATERIAL_DIGEST_VERSION,
    guest_deploy_material_sha256,
)
from tirosh_vitalserver.devtools.adapters.toolchain.gzip_compression import (
    validate_gzip_file,
)
from tirosh_vitalserver.devtools.application.inputs import RootfsBaseInput


def test_require_stopped_lifecycle_accepts_stopped_vm(tmp_path):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    source.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    write_vm_lifecycle_owner(source, state="stopped")

    require_stopped_lifecycle(source)


def test_require_stopped_lifecycle_ignores_stale_json_diagnostic(tmp_path):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    diagnostic = tmp_path / "vm" / "run" / "vm-lifecycle.json"
    source.parent.mkdir(parents=True)
    diagnostic.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    diagnostic.write_text(json.dumps({"state": "failed"}), encoding="utf-8")
    write_vm_lifecycle_owner(source, state="stopped")

    require_stopped_lifecycle(source)


def test_require_stopped_lifecycle_rejects_missing_sqlite_owner(tmp_path):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    source.parent.mkdir(parents=True)
    source.write_bytes(b"disk")

    with pytest.raises(SystemExit, match="VM lifecycle SQLite owner is missing"):
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


def test_require_ready_marker_rejects_missing_identity_cleanup_proof(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_ready_marker(source, identity_cleanup=None)

    with pytest.raises(SystemExit, match="identity cleanup proof"):
        require_ready_marker(source, expected_run_id="run-test")


def test_require_ready_marker_rejects_missing_guest_tools_dependency_proof(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_ready_marker(source, python_dependencies=None)

    with pytest.raises(SystemExit, match="Guest Tools dependency proof"):
        require_ready_marker(source, expected_run_id="run-test")


def test_require_ready_marker_rejects_incomplete_guest_tools_dependency_proof(
    tmp_path,
):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_ready_marker(
        source,
        python_dependencies={
            "status": "passed",
            "proof": "/opt/tirosh/guest-tools/install-proof.json",
            "target": "linux-aarch64",
            "dependencies": {"alembic": "1.16.5"},
        },
    )

    with pytest.raises(SystemExit, match="invalid Guest Tools dependency proof"):
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


def test_require_runtime_manifest_rejects_missing_runtime_data_proof(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, runtime_data=None)

    with pytest.raises(SystemExit, match="runtime data mount proof"):
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


def test_require_runtime_manifest_rejects_missing_docker_image_proof(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, docker_images=None)

    with pytest.raises(SystemExit, match="Docker image architecture/digest proof"):
        require_runtime_manifest(source)


def test_require_runtime_manifest_rejects_missing_inode_resource_proof(tmp_path):
    source = rootfs_source_with_lifecycle(tmp_path)
    write_runtime_manifest(source, include_inode_proof=False)

    with pytest.raises(SystemExit, match="availableInodes"):
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
    source.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    write_vm_lifecycle_owner(source, state="stopping")

    with pytest.raises(SystemExit, match="lifecycle is not stopped"):
        require_stopped_lifecycle(source)


def test_require_stopped_lifecycle_rejects_terminal_failure_reason(tmp_path):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    source.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    write_vm_lifecycle_owner(
        source,
        state="failed",
        terminal_reason="guest-kernel-panic",
    )

    with pytest.raises(SystemExit, match="lifecycle failed"):
        require_stopped_lifecycle(source)


def test_validate_gzip_file_rejects_corrupt_output(tmp_path):
    output = tmp_path / "rootfs-base.raw.gz"
    output.write_bytes(b"not a gzip")

    with pytest.raises(SystemExit, match="gzip validation failed"):
        validate_gzip_file(output, expected_uncompressed_size=4)


def test_run_rootfs_base_rejects_corrupt_compressor_output(tmp_path, monkeypatch):
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    output = tmp_path / "rootfs-base.raw.gz"
    source.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    write_vm_lifecycle_owner(source, state="stopped")
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


def test_run_rootfs_base_writes_artifact_manifest(tmp_path, monkeypatch):
    source = rootfs_source_with_lifecycle(tmp_path)
    output = tmp_path / "rootfs-base.raw.gz"
    write_runtime_manifest(source)
    write_ready_marker(source)
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )

    run_rootfs_base(RootfsBaseInput(
        source=source,
        output=output,
        force=True,
        compression_threads=1,
        expected_run_id="run-test",
    ))

    manifest = rootfs_artifact_manifest_path(output)
    document = json.loads(manifest.read_text(encoding="utf-8"))
    assert document["schemaVersion"] == ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION
    assert document["artifact"]["name"] == "rootfs-base.raw.gz"
    assert document["artifact"]["path"] == str(output)
    assert document["artifact"]["sizeBytes"] == output.stat().st_size
    assert document["artifact"]["sha256"] == sha256_file(output)
    assert document["source"]["diskPath"] == str(source)
    assert document["source"]["diskSizeBytes"] == source.stat().st_size
    assert document["source"]["runId"] == "run-test"
    assert document["guestDeploy"] == {
        "path": "data/deploy",
        "materialDigestVersion": GUEST_DEPLOY_MATERIAL_DIGEST_VERSION,
        "materialSha256": guest_deploy_material_sha256(
            source.parent.parent / "data/deploy"
        ),
    }
    assert document["proof"]["cleanupStatus"] == "passed"
    assert "docker-image-load" in document["proof"]["requiredStages"]


def test_run_rootfs_base_rebuilds_cached_artifact_without_manifest(
    tmp_path,
    monkeypatch,
):
    source = rootfs_source_with_lifecycle(tmp_path)
    output = tmp_path / "rootfs-base.raw.gz"
    write_runtime_manifest(source)
    write_ready_marker(source)
    write_gzip(output, b"old")
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )

    run_rootfs_base(RootfsBaseInput(
        source=source,
        output=output,
        force=False,
        compression_threads=1,
        expected_run_id="run-test",
    ))

    assert gzip.decompress(output.read_bytes()) == b"disk"
    assert rootfs_artifact_manifest_path(output).is_file()


def test_require_rootfs_artifact_manifest_rejects_checksum_mismatch(
    tmp_path,
    monkeypatch,
):
    source = rootfs_source_with_lifecycle(tmp_path)
    output = tmp_path / "rootfs-base.raw.gz"
    write_runtime_manifest(source)
    write_ready_marker(source)
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )
    run_rootfs_base(RootfsBaseInput(
        source=source,
        output=output,
        force=True,
        compression_threads=1,
        expected_run_id="run-test",
    ))
    output.write_bytes(b"x" * output.stat().st_size)

    with pytest.raises(SystemExit, match=r"artifact\.sha256"):
        require_rootfs_artifact_manifest(
            output,
            source,
            runtime_manifest=require_runtime_manifest(
                source,
                expected_run_id="run-test",
            ),
            ready_marker=require_ready_marker(source, expected_run_id="run-test"),
        )


def test_require_rootfs_artifact_manifest_rejects_changed_guest_deploy_material(
    tmp_path,
    monkeypatch,
):
    source = rootfs_source_with_lifecycle(tmp_path)
    output = tmp_path / "rootfs-base.raw.gz"
    write_runtime_manifest(source)
    write_ready_marker(source)
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )
    run_rootfs_base(RootfsBaseInput(
        source=source,
        output=output,
        force=True,
        compression_threads=1,
        expected_run_id="run-test",
    ))
    (source.parent.parent / "data/deploy/bootstrap.sh").write_text(
        "changed\n",
        encoding="utf-8",
    )

    with pytest.raises(SystemExit, match="Guest deploy material does not match"):
        require_rootfs_artifact_manifest(
            output,
            source,
            runtime_manifest=require_runtime_manifest(
                source,
                expected_run_id="run-test",
            ),
            ready_marker=require_ready_marker(source, expected_run_id="run-test"),
        )


def test_require_rootfs_artifact_guest_deploy_match_accepts_matching_receipt(
    tmp_path,
    monkeypatch,
):
    source = rootfs_source_with_lifecycle(tmp_path)
    output = tmp_path / "rootfs-base.raw.gz"
    write_runtime_manifest(source)
    write_ready_marker(source)
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )
    run_rootfs_base(RootfsBaseInput(
        source=source,
        output=output,
        force=True,
        compression_threads=1,
        expected_run_id="run-test",
    ))

    material = require_rootfs_artifact_guest_deploy_match(
        output,
        source.parent.parent / "data/deploy",
    )

    assert material == guest_deploy_material_sha256(
        source.parent.parent / "data/deploy"
    )


def test_require_rootfs_artifact_guest_deploy_match_rejects_static_metadata_change(
    tmp_path,
    monkeypatch,
):
    source = rootfs_source_with_lifecycle(tmp_path)
    output = tmp_path / "rootfs-base.raw.gz"
    write_runtime_manifest(source)
    write_ready_marker(source)
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )
    run_rootfs_base(RootfsBaseInput(
        source=source,
        output=output,
        force=True,
        compression_threads=1,
        expected_run_id="run-test",
    ))
    metadata = source.parent.parent / "data/deploy/build-metadata/rootfs-input.json"
    document = json.loads(metadata.read_text(encoding="utf-8"))
    document["dockerImages"]["platform"] = "linux/amd64"
    metadata.write_text(json.dumps(document), encoding="utf-8")

    with pytest.raises(SystemExit, match="does not match rootfs artifact receipt"):
        require_rootfs_artifact_guest_deploy_match(
            output,
            source.parent.parent / "data/deploy",
        )


def rootfs_source_with_lifecycle(tmp_path: Path) -> Path:
    source = tmp_path / "vm" / "runtime" / "vm-disk.img"
    source.parent.mkdir(parents=True)
    source.write_bytes(b"disk")
    write_vm_lifecycle_owner(source, state="stopped")
    deploy = tmp_path / "vm" / "data" / "deploy"
    (deploy / "build-metadata").mkdir(parents=True)
    (deploy / "build-metadata/rootfs-input.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "guestClockUtc": "2026-06-11T00:00:00Z",
                "runtimeBootSmoke": {"enabled": False},
                "dockerImages": {"platform": "linux/arm64"},
                "runtimeData": {
                    "diskImageName": "runtime-data.img",
                    "diskSize": "16G",
                    "filesystemLabel": "vital-runtime",
                    "mountPath": "/mnt/runtime",
                    "dockerDataRoot": "/mnt/runtime/docker",
                    "containerdRoot": "/mnt/runtime/containerd",
                },
                "ubuntu": {
                    "aptSnapshot": "20250313T000000Z",
                    "baseUrl": "https://example.invalid/release",
                    "cacheKey": "release-abcd",
                },
            }
        ),
        encoding="utf-8",
    )
    (deploy / "bootstrap.sh").write_text("#!/bin/sh\n", encoding="utf-8")
    return source


def write_vm_lifecycle_owner(
    source: Path,
    *,
    state: str,
    terminal_reason: str | None = None,
    message: str | None = None,
) -> None:
    database = source.parent / "runtime-state.sqlite"
    with sqlite3.connect(database) as connection:
        connection.execute(
            """
            CREATE TABLE vm_lifecycle (
              singleton_id INTEGER PRIMARY KEY,
              state TEXT NOT NULL,
              terminal_reason TEXT,
              message TEXT
            )
            """
        )
        connection.execute(
            """
            INSERT INTO vm_lifecycle(singleton_id, state, terminal_reason, message)
            VALUES (1, ?, ?, ?)
            """,
            (state, terminal_reason, message),
        )


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
    runtime_data: dict[str, object] | None | bool = True,
    docker_images: dict[str, object] | None | bool = True,
    include_inode_proof: bool = True,
) -> None:
    manifest = source.parent.parent / "data" / "run" / "rootfs-runtime-manifest.json"
    manifest.parent.mkdir(parents=True)
    stage_statuses = stage_statuses or {}
    omitted_stages = omitted_stages or set()
    stages = []
    for name in (
        "runtime-data-mount",
        "runtime-data-configure",
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
        if name == "disk-space":
            details = {
                "filesystems": [
                    {
                        "path": "/",
                        "availableKiB": 8_387_584,
                        "minimumKiB": 1_048_576,
                        "minimumInodes": 1_024,
                        "passed": True,
                    }
                ]
            }
            if include_inode_proof:
                details["filesystems"][0]["availableInodes"] = 524_288
        else:
            details = {}
        stages.append({
            "name": name,
            "status": status,
            "startedAt": "2026-06-11T00:00:00Z",
            "completedAt": "2026-06-11T00:00:01Z",
            "message": message,
            "details": details,
        })
    if runtime_data is True:
        runtime_data_document: dict[str, object] | None = {
            "status": "passed",
            "mountPath": "/mnt/runtime",
            "dockerDataRoot": "/mnt/runtime/docker",
            "containerdRoot": "/mnt/runtime/containerd",
        }
    elif isinstance(runtime_data, dict):
        runtime_data_document = runtime_data
    else:
        runtime_data_document = None
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
    if runtime_data_document is not None:
        document["runtimeData"] = runtime_data_document
    if docker_images is True:
        document["dockerImages"] = {
            "status": "passed",
            "message": "Docker image bundle matched guest architecture and loaded",
            "bundle": "/mnt/tirosh/deploy/docker-images/vitalserver-images.tar.gz",
            "bundleBytes": 6,
            "bundleSha256": "sha256-test",
            "platform": "linux/arm64",
            "guestArchitecture": "aarch64",
        }
    elif isinstance(docker_images, dict):
        document["dockerImages"] = docker_images
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


def write_ready_marker(
    source: Path,
    *,
    run_id: str = "run-test",
    identity_cleanup: dict[str, object] | None | bool = True,
    python_dependencies: dict[str, object] | None | bool = True,
) -> None:
    marker = source.parent.parent / "data" / "run" / "rootfs-ready"
    marker.parent.mkdir(parents=True, exist_ok=True)
    document = {
        "schemaVersion": 1,
        "runId": run_id,
        "readyAt": "2026-06-11T00:00:02Z",
    }
    if identity_cleanup is True:
        document["identityCleanup"] = {
            "status": "passed",
            "proof": str(
                source.parent.parent / "data/run/rootfs-identity-cleanup.json"
            ),
        }
    elif isinstance(identity_cleanup, dict):
        document["identityCleanup"] = identity_cleanup
    if python_dependencies is True:
        document["pythonDependencies"] = {
            "status": "passed",
            "proof": "/opt/tirosh/guest-tools/install-proof.json",
            "target": "linux-aarch64",
            "dependencies": {"alembic": "1.16.5", "sqlalchemy": "2.0.51"},
        }
    elif isinstance(python_dependencies, dict):
        document["pythonDependencies"] = python_dependencies
    marker.write_text(
        json.dumps(document),
        encoding="utf-8",
    )


def write_gzip(path: Path, payload: bytes) -> None:
    with gzip.open(path, "wb") as handle:
        handle.write(payload)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
