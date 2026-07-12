from __future__ import annotations

import hashlib
import json
import uuid
from datetime import UTC, datetime
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle import (
    running_vm_processes_for_home,
)
from tirosh_vitalserver.devtools.adapters.toolchain.gzip_compression import (
    compression_threads,
    gzip_file,
    validate_gzip_file,
)
from tirosh_vitalserver.devtools.application.inputs import RootfsBaseInput

ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION = 1
REQUIRED_ROOTFS_STAGES = (
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
)


def run_rootfs_base(input: RootfsBaseInput) -> int:
    source = input.source
    output = input.output
    force = input.force

    if not source.is_file() or source.stat().st_size == 0:
        raise SystemExit(f"missing rootfs source: {source}")
    require_stopped_lifecycle(source)
    require_no_running_launcher(source)
    runtime_manifest = require_runtime_manifest(
        source,
        expected_run_id=input.expected_run_id,
    )
    ready_marker = require_ready_marker(source, expected_run_id=input.expected_run_id)
    if (
        output.exists()
        and not force
        and output.stat().st_mtime >= source.stat().st_mtime
    ):
        try:
            require_rootfs_artifact_manifest(
                output,
                source,
                runtime_manifest=runtime_manifest,
                ready_marker=ready_marker,
            )
        except SystemExit as error:
            print(f"rootfs artifact proof is invalid; rebuilding: {error}")
        else:
            print(f"exists {output}")
            return 0

    output.parent.mkdir(parents=True, exist_ok=True)
    threads = compression_threads(input.compression_threads)
    temporary_output = output.with_name(f".{output.name}.{uuid.uuid4()}.tmp")
    manifest = rootfs_artifact_manifest_path(output)
    temporary_manifest = manifest.with_name(f".{manifest.name}.{uuid.uuid4()}.tmp")
    print(f"compressing {source} -> {output}")
    try:
        gzip_file(source, temporary_output, threads=threads)
        validate_gzip_file(
            temporary_output,
            expected_uncompressed_size=source.stat().st_size,
        )
        write_rootfs_artifact_manifest(
            temporary_manifest,
            artifact=temporary_output,
            final_artifact=output,
            source=source,
            runtime_manifest=runtime_manifest,
            ready_marker=ready_marker,
            compression_threads=threads,
        )
        temporary_output.replace(output)
        temporary_manifest.replace(manifest)
    finally:
        if temporary_output.exists():
            temporary_output.unlink()
        if temporary_manifest.exists():
            temporary_manifest.unlink()
    print(f"rootfs base is ready: {output}")
    return 0


def require_stopped_lifecycle(source: Path) -> None:
    runtime_dir = source.parent
    vm_home = runtime_dir.parent
    lifecycle = vm_home / "run" / "vm-lifecycle.json"
    if not lifecycle.is_file():
        raise SystemExit(
            "error: rootfs source VM lifecycle is missing; stop the golden VM "
            f"cleanly before compressing rootfs: {lifecycle}"
        )
    try:
        document = json.loads(lifecycle.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"error: rootfs source VM lifecycle is unreadable: {lifecycle}: {error}"
        ) from error
    state = document.get("state")
    if state != "stopped":
        raise SystemExit(
            "error: rootfs source VM lifecycle is not stopped; refusing to "
            f"compress a VM disk with unproven shutdown state: state={state}"
        )
    terminal_reason = document.get("terminalReason")
    if terminal_reason is not None:
        raise SystemExit(
            "error: rootfs source VM lifecycle has terminal failure reason; "
            f"refusing to compress failed VM disk: terminalReason={terminal_reason}"
        )


def require_no_running_launcher(source: Path) -> None:
    vm_home = source.parent.parent
    pids = running_vm_processes_for_home(vm_home)
    if pids:
        raise SystemExit(
            "error: VM launcher process is still running for rootfs source; "
            f"refusing to compress mutable runtime files: {vm_home}: pids={pids}"
        )


def require_runtime_manifest(
    source: Path,
    *,
    expected_run_id: str | None = None,
) -> dict[str, object]:
    runtime_dir = source.parent
    vm_home = runtime_dir.parent
    manifest = vm_home / "data" / "run" / "rootfs-runtime-manifest.json"
    if not manifest.is_file():
        raise SystemExit(
            "error: rootfs runtime manifest is missing; rebuild the golden "
            f"rootfs with Docker runtime smoke validation: {manifest}"
        )
    try:
        document = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"error: rootfs runtime manifest is unreadable: {manifest}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise SystemExit(
            "error: rootfs runtime manifest is invalid: expected object: "
            f"{manifest}"
        )
    schema_version = document.get("schemaVersion")
    if schema_version != 2:
        raise SystemExit(
            "error: rootfs runtime manifest schema is unsupported; "
            f"expected=2 actual={schema_version} manifest={manifest}"
        )
    require_matching_run_id(
        document,
        expected_run_id=expected_run_id,
        source_name="rootfs runtime manifest",
        source_path=manifest,
    )
    runtime_data = document.get("runtimeData")
    if (
        not isinstance(runtime_data, dict)
        or runtime_data.get("status") != "passed"
        or not non_empty_string(runtime_data.get("mountPath"))
        or not non_empty_string(runtime_data.get("dockerDataRoot"))
        or not non_empty_string(runtime_data.get("containerdRoot"))
    ):
        raise SystemExit(
            "error: rootfs runtime manifest is missing passed runtime data "
            f"mount proof; manifest={manifest}"
        )
    require_docker_images_proof(document, manifest)
    ubuntu = document.get("ubuntu")
    if (
        not isinstance(ubuntu, dict)
        or ubuntu.get("metadataStatus") != "loaded"
        or not non_empty_string(ubuntu.get("baseUrl"))
        or not non_empty_string(ubuntu.get("cacheKey"))
        or not non_empty_string(ubuntu.get("aptSnapshot"))
        or not non_empty_string(ubuntu.get("kernel"))
    ):
        raise SystemExit(
            "error: rootfs runtime manifest is missing explicit Ubuntu input "
            "metadata or kernel; "
            f"manifest={manifest}"
        )
    require_apt_plan(
        document,
        manifest,
        expected_run_id=str(document["runId"]),
        expected_snapshot=str(ubuntu["aptSnapshot"]),
    )
    stages = document.get("stages")
    if not isinstance(stages, list):
        raise SystemExit(
            "error: rootfs runtime manifest is missing stage results; "
            f"manifest={manifest}"
        )
    for stage_name in REQUIRED_ROOTFS_STAGES:
        require_stage_passed(stages, stage_name, manifest)
    require_disk_space_resource_proof(stages, manifest)
    cleanup = document.get("cleanup")
    cleanup_status = cleanup.get("status") if isinstance(cleanup, dict) else None
    if cleanup_status != "passed":
        raise SystemExit(
            "error: rootfs smoke cleanup did not pass; refusing to compress "
            f"unproven rootfs: status={cleanup_status} manifest={manifest}"
        )
    return document


def require_ready_marker(
    source: Path,
    *,
    expected_run_id: str | None = None,
) -> dict[str, object]:
    marker = source.parent.parent / "data" / "run" / "rootfs-ready"
    if not marker.is_file():
        raise SystemExit(
            "error: rootfs ready marker is missing; refusing to compress "
            f"unproven rootfs: {marker}"
        )
    try:
        document = json.loads(marker.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"error: rootfs ready marker is unreadable: {marker}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise SystemExit(
            f"error: rootfs ready marker is invalid: expected object: {marker}"
        )
    require_matching_run_id(
        document,
        expected_run_id=expected_run_id,
        source_name="rootfs ready marker",
        source_path=marker,
    )
    identity_cleanup = document.get("identityCleanup")
    if (
        not isinstance(identity_cleanup, dict)
        or identity_cleanup.get("status") != "passed"
        or not non_empty_string(identity_cleanup.get("proof"))
    ):
        raise SystemExit(
            "error: rootfs ready marker is missing passed identity cleanup "
            f"proof: {marker}"
        )
    require_guest_tools_dependency_proof(document, marker)
    return document


def require_guest_tools_dependency_proof(
    document: dict[str, object],
    marker: Path,
) -> None:
    dependencies_proof = document.get("pythonDependencies")
    if not isinstance(dependencies_proof, dict):
        raise SystemExit(
            "error: rootfs ready marker is missing Guest Tools dependency proof: "
            f"{marker}"
        )
    dependencies = dependencies_proof.get("dependencies")
    if (
        dependencies_proof.get("status") != "passed"
        or not non_empty_string(dependencies_proof.get("proof"))
        or not non_empty_string(dependencies_proof.get("target"))
        or not isinstance(dependencies, dict)
        or not non_empty_string(dependencies.get("alembic"))
        or not non_empty_string(dependencies.get("sqlalchemy"))
    ):
        raise SystemExit(
            "error: rootfs ready marker has invalid Guest Tools dependency proof: "
            f"{marker}"
        )


def rootfs_artifact_manifest_path(artifact: Path) -> Path:
    return artifact.with_name(f"{artifact.name}.manifest.json")


def write_rootfs_artifact_manifest(
    destination: Path,
    *,
    artifact: Path,
    final_artifact: Path,
    source: Path,
    runtime_manifest: dict[str, object],
    ready_marker: dict[str, object],
    compression_threads: int,
) -> None:
    run_id = require_same_proof_run_id(runtime_manifest, ready_marker)
    document = {
        "schemaVersion": ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION,
        "createdAt": utc_now(),
        "artifact": {
            "name": final_artifact.name,
            "path": str(final_artifact),
            "sizeBytes": artifact.stat().st_size,
            "sha256": sha256_file(artifact),
            "compression": "gzip",
            "compressionThreads": compression_threads,
        },
        "source": {
            "diskPath": str(source),
            "diskSizeBytes": source.stat().st_size,
            "runId": run_id,
            "runtimeManifest": str(runtime_manifest_path(source)),
            "readyMarker": str(ready_marker_path(source)),
        },
        "proof": {
            "runtimeManifestSchemaVersion": runtime_manifest.get("schemaVersion"),
            "readyMarkerSchemaVersion": ready_marker.get("schemaVersion"),
            "requiredStages": list(REQUIRED_ROOTFS_STAGES),
            "cleanupStatus": read_cleanup_status(runtime_manifest),
            "ubuntu": runtime_manifest.get("ubuntu"),
            "runtimeData": runtime_manifest.get("runtimeData"),
            "pythonDependencies": ready_marker.get("pythonDependencies"),
        },
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def require_rootfs_artifact_manifest(
    artifact: Path,
    source: Path,
    *,
    runtime_manifest: dict[str, object],
    ready_marker: dict[str, object],
) -> dict[str, object]:
    manifest = rootfs_artifact_manifest_path(artifact)
    if not manifest.is_file():
        raise SystemExit(
            "error: rootfs artifact manifest is missing; refusing to reuse "
            f"unproven artifact: {manifest}"
        )
    try:
        document = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"error: rootfs artifact manifest is unreadable: {manifest}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise SystemExit(
            f"error: rootfs artifact manifest is invalid: expected object: {manifest}"
        )
    schema_version = document.get("schemaVersion")
    if schema_version != ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION:
        raise SystemExit(
            "error: rootfs artifact manifest schema is unsupported; "
            f"expected={ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION} "
            f"actual={schema_version} manifest={manifest}"
        )
    artifact_document = document.get("artifact")
    source_document = document.get("source")
    proof_document = document.get("proof")
    if not isinstance(artifact_document, dict):
        raise SystemExit(f"error: rootfs artifact proof is missing: {manifest}")
    if not isinstance(source_document, dict):
        raise SystemExit(f"error: rootfs artifact source proof is missing: {manifest}")
    if not isinstance(proof_document, dict):
        raise SystemExit(f"error: rootfs artifact runtime proof is missing: {manifest}")

    require_same_proof_run_id(runtime_manifest, ready_marker)
    expected_run_id = runtime_manifest.get("runId")
    checks = {
        "artifact.name": artifact.name,
        "artifact.path": str(artifact),
        "artifact.sizeBytes": artifact.stat().st_size,
        "artifact.sha256": sha256_file(artifact),
        "source.diskPath": str(source),
        "source.diskSizeBytes": source.stat().st_size,
        "source.runId": expected_run_id,
        "source.runtimeManifest": str(runtime_manifest_path(source)),
        "source.readyMarker": str(ready_marker_path(source)),
        "proof.cleanupStatus": "passed",
    }
    actuals = {
        "artifact.name": artifact_document.get("name"),
        "artifact.path": artifact_document.get("path"),
        "artifact.sizeBytes": artifact_document.get("sizeBytes"),
        "artifact.sha256": artifact_document.get("sha256"),
        "source.diskPath": source_document.get("diskPath"),
        "source.diskSizeBytes": source_document.get("diskSizeBytes"),
        "source.runId": source_document.get("runId"),
        "source.runtimeManifest": source_document.get("runtimeManifest"),
        "source.readyMarker": source_document.get("readyMarker"),
        "proof.cleanupStatus": proof_document.get("cleanupStatus"),
    }
    for name, expected in checks.items():
        actual = actuals[name]
        if actual != expected:
            raise SystemExit(
                "error: rootfs artifact manifest does not match current proof; "
                f"field={name} expected={expected} actual={actual} "
                f"manifest={manifest}"
            )
    required_stages = proof_document.get("requiredStages")
    if required_stages != list(REQUIRED_ROOTFS_STAGES):
        raise SystemExit(
            "error: rootfs artifact manifest required stages do not match "
            f"current contract; manifest={manifest}"
        )
    return document


def require_same_proof_run_id(
    runtime_manifest: dict[str, object],
    ready_marker: dict[str, object],
) -> str:
    run_id = runtime_manifest.get("runId")
    ready_run_id = ready_marker.get("runId")
    if not non_empty_string(run_id):
        raise SystemExit("error: rootfs runtime manifest is missing runId")
    if run_id != ready_run_id:
        raise SystemExit(
            "error: rootfs runtime manifest and ready marker runId differ; "
            f"manifestRunId={run_id} readyRunId={ready_run_id}"
        )
    return str(run_id)


def runtime_manifest_path(source: Path) -> Path:
    return source.parent.parent / "data" / "run" / "rootfs-runtime-manifest.json"


def ready_marker_path(source: Path) -> Path:
    return source.parent.parent / "data" / "run" / "rootfs-ready"


def read_cleanup_status(runtime_manifest: dict[str, object]) -> object:
    cleanup = runtime_manifest.get("cleanup")
    if not isinstance(cleanup, dict):
        return None
    return cleanup.get("status")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def utc_now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def require_matching_run_id(
    document: dict[str, object],
    *,
    expected_run_id: str | None,
    source_name: str,
    source_path: Path,
) -> None:
    run_id = document.get("runId")
    if not non_empty_string(run_id):
        raise SystemExit(
            f"error: {source_name} is missing explicit runId: {source_path}"
        )
    if expected_run_id is not None and run_id != expected_run_id:
        raise SystemExit(
            f"error: {source_name} runId does not match current golden rootfs "
            f"run: expected={expected_run_id} actual={run_id} path={source_path}"
        )


def require_stage_passed(
    stages: list[object],
    name: str,
    manifest: Path,
) -> dict[str, object]:
    stage = next(
        (
            value
            for value in stages
            if isinstance(value, dict) and value.get("name") == name
        ),
        None,
    )
    if not isinstance(stage, dict):
        raise SystemExit(
            f"error: rootfs runtime manifest is missing {name} stage; "
            f"manifest={manifest}"
        )
    status = stage.get("status")
    if status != "passed":
        message = stage.get("message")
        raise SystemExit(
            f"error: rootfs {name} stage did not pass; refusing to compress "
            f"unproven rootfs: status={status} message={message}"
        )
    return stage


def require_docker_images_proof(
    document: dict[str, object],
    manifest: Path,
) -> None:
    docker_images = document.get("dockerImages")
    if (
        not isinstance(docker_images, dict)
        or docker_images.get("status") != "passed"
        or not non_empty_string(docker_images.get("platform"))
        or not non_empty_string(docker_images.get("guestArchitecture"))
        or not non_empty_string(docker_images.get("bundleSha256"))
        or not isinstance(docker_images.get("bundleBytes"), int)
    ):
        raise SystemExit(
            "error: rootfs runtime manifest is missing passed Docker image "
            f"architecture/digest proof; manifest={manifest}"
        )


def require_disk_space_resource_proof(stages: list[object], manifest: Path) -> None:
    stage = require_stage_passed(stages, "disk-space", manifest)
    details = stage.get("details")
    filesystems = details.get("filesystems") if isinstance(details, dict) else None
    if not isinstance(filesystems, list) or not filesystems:
        raise SystemExit(
            "error: rootfs disk-space stage is missing filesystem resource proof; "
            f"manifest={manifest}"
        )
    for filesystem in filesystems:
        if not isinstance(filesystem, dict):
            raise SystemExit(
                "error: rootfs disk-space filesystem proof is invalid; "
                f"manifest={manifest}"
            )
        path = filesystem.get("path")
        if not non_empty_string(path):
            raise SystemExit(
                "error: rootfs disk-space filesystem proof is missing path; "
                f"manifest={manifest}"
            )
        for field_name in (
            "availableKiB",
            "minimumKiB",
            "availableInodes",
            "minimumInodes",
        ):
            if not isinstance(filesystem.get(field_name), int):
                raise SystemExit(
                    "error: rootfs disk-space filesystem proof is missing "
                    f"{field_name}; path={path} manifest={manifest}"
                )
        if filesystem.get("passed") is not True:
            raise SystemExit(
                "error: rootfs disk-space filesystem proof did not pass; "
                f"path={path} manifest={manifest}"
            )


def require_apt_plan(
    document: dict[str, object],
    manifest: Path,
    *,
    expected_run_id: str,
    expected_snapshot: str,
) -> None:
    apt = document.get("apt")
    if not isinstance(apt, dict):
        raise SystemExit(
            "error: rootfs runtime manifest is missing apt plan proof; "
            f"manifest={manifest}"
        )
    status = apt.get("status")
    if status != "allowed":
        raise SystemExit(
            "error: rootfs apt plan is not allowed; refusing to compress "
            f"unproven rootfs: status={status} manifest={manifest}"
        )
    run_id = apt.get("runId")
    if run_id != expected_run_id:
        raise SystemExit(
            "error: rootfs apt plan runId does not match manifest; "
            f"expected={expected_run_id} actual={run_id} manifest={manifest}"
        )
    snapshot = apt.get("snapshot")
    if snapshot != expected_snapshot:
        raise SystemExit(
            "error: rootfs apt plan snapshot does not match Ubuntu input; "
            f"expected={expected_snapshot} actual={snapshot} manifest={manifest}"
        )
    blocked = apt.get("blockedUpgrades")
    if not isinstance(blocked, list):
        raise SystemExit(
            "error: rootfs apt plan is missing blocked upgrade proof; "
            f"manifest={manifest}"
        )
    if blocked:
        raise SystemExit(
            "error: rootfs apt plan mutates base runtime packages; refusing "
            f"to compress unproven rootfs: blockedUpgrades={blocked}"
        )


def non_empty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())
