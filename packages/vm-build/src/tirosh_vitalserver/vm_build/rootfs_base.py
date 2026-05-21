from __future__ import annotations

from argparse import Namespace
from pathlib import Path

from .compression import compression_threads, gzip_file
from .config import parse_bool


def run_rootfs_base(args: Namespace) -> int:
    source = args.source
    output = args.output
    force = args.force

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
    threads = compression_threads(args.compression_threads)
    print(f"compressing {source} -> {output}")
    gzip_file(source, output, threads=threads)
    print(f"rootfs base is ready: {output}")
    return 0


def add_rootfs_base_arguments(parser) -> None:
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--force", type=parse_bool, default=False)
    parser.add_argument("--compression-threads", type=int)
