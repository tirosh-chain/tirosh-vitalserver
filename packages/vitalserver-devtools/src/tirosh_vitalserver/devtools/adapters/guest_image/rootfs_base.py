from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.toolchain.gzip_compression import (
    compression_threads,
    gzip_file,
)
from tirosh_vitalserver.devtools.application.inputs import RootfsBaseInput


def run_rootfs_base(input: RootfsBaseInput) -> int:
    source = input.source
    output = input.output
    force = input.force

    if not source.is_file() or source.stat().st_size == 0:
        raise SystemExit(f"missing rootfs source: {source}")
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
    print(f"rootfs base is ready: {output}")
    return 0
