from __future__ import annotations

import json
import uuid
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


def run_rootfs_base(input: RootfsBaseInput) -> int:
    source = input.source
    output = input.output
    force = input.force

    if not source.is_file() or source.stat().st_size == 0:
        raise SystemExit(f"missing rootfs source: {source}")
    require_stopped_lifecycle(source)
    require_no_running_launcher(source)
    require_runtime_manifest(source, expected_run_id=input.expected_run_id)
    require_ready_marker(source, expected_run_id=input.expected_run_id)
    if (
        output.exists()
        and not force
        and output.stat().st_mtime >= source.stat().st_mtime
    ):
        print(f"exists {output}")
        return 0

    output.parent.mkdir(parents=True, exist_ok=True)
    threads = compression_threads(input.compression_threads)
    temporary_output = output.with_name(f".{output.name}.{uuid.uuid4()}.tmp")
    print(f"compressing {source} -> {output}")
    try:
        gzip_file(source, temporary_output, threads=threads)
        validate_gzip_file(
            temporary_output,
            expected_uncompressed_size=source.stat().st_size,
        )
        temporary_output.replace(output)
    finally:
        if temporary_output.exists():
            temporary_output.unlink()
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
) -> None:
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
    require_stage_passed(stages, "docker-service", manifest)
    require_stage_passed(stages, "runtime-version", manifest)
    require_stage_passed(stages, "docker-image-load", manifest)
    require_stage_passed(stages, "docker-smoke", manifest)
    require_stage_passed(stages, "disk-space", manifest)
    require_stage_passed(stages, "compose-build", manifest)
    require_stage_passed(stages, "compose-up", manifest)
    require_stage_passed(stages, "edge-ready", manifest)
    cleanup = document.get("cleanup")
    cleanup_status = cleanup.get("status") if isinstance(cleanup, dict) else None
    if cleanup_status != "passed":
        raise SystemExit(
            "error: rootfs smoke cleanup did not pass; refusing to compress "
            f"unproven rootfs: status={cleanup_status} manifest={manifest}"
        )


def require_ready_marker(
    source: Path,
    *,
    expected_run_id: str | None = None,
) -> None:
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


def require_stage_passed(stages: list[object], name: str, manifest: Path) -> None:
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
