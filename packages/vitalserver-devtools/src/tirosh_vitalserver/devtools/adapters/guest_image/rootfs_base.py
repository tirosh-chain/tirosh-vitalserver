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
    docker_smoke = document.get("dockerSmoke")
    if not isinstance(docker_smoke, dict):
        raise SystemExit(
            "error: rootfs runtime manifest is missing dockerSmoke result; "
            f"manifest={manifest}"
        )
    smoke_status = docker_smoke.get("status")
    if smoke_status != "passed":
        smoke_message = docker_smoke.get("message")
        raise SystemExit(
            "error: rootfs Docker runtime smoke did not pass; refusing to "
            f"compress unproven rootfs: status={smoke_status} message={smoke_message}"
        )
    bpf_jit = document.get("bpfJIT")
    if not isinstance(bpf_jit, dict):
        raise SystemExit(
            "error: rootfs runtime manifest is missing bpfJIT guard; "
            f"manifest={manifest}"
        )
    bpf_jit_enable = bpf_jit.get("net.core.bpf_jit_enable")
    if bpf_jit_enable != "0":
        raise SystemExit(
            "error: rootfs BPF JIT guard is not applied; refusing to compress "
            f"rootfs that may kernel panic during Docker runtime: "
            f"net.core.bpf_jit_enable={bpf_jit_enable}"
        )
