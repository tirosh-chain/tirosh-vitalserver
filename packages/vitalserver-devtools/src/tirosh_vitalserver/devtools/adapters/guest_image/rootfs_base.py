from __future__ import annotations

import json
from pathlib import Path

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
    require_runtime_manifest(source)
    if (
        output.exists()
        and not force
        and output.stat().st_mtime >= source.stat().st_mtime
    ):
        print(f"exists {output}")
        return 0

    output.parent.mkdir(parents=True, exist_ok=True)
    threads = compression_threads(input.compression_threads)
    print(f"compressing {source} -> {output}")
    gzip_file(source, output, threads=threads)
    validate_gzip_file(output, expected_uncompressed_size=source.stat().st_size)
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


def require_runtime_manifest(source: Path) -> None:
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
    ubuntu = document.get("ubuntu")
    if (
        not isinstance(ubuntu, dict)
        or ubuntu.get("metadataStatus") != "loaded"
        or not non_empty_string(ubuntu.get("baseUrl"))
        or not non_empty_string(ubuntu.get("cacheKey"))
        or not non_empty_string(ubuntu.get("kernel"))
    ):
        raise SystemExit(
            "error: rootfs runtime manifest is missing explicit Ubuntu input "
            "metadata or kernel; "
            f"manifest={manifest}"
        )
    stages = document.get("stages")
    if not isinstance(stages, list):
        raise SystemExit(
            "error: rootfs runtime manifest is missing stage results; "
            f"manifest={manifest}"
        )
    require_stage_passed(stages, "docker-smoke", manifest)
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


def non_empty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())
