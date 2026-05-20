from __future__ import annotations

import gzip
import shutil
from argparse import Namespace
from pathlib import Path

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
    temporary = output.with_name(output.name + ".tmp")
    temporary.unlink(missing_ok=True)

    print(f"compressing {source} -> {output}")
    with source.open("rb") as source_file, gzip.open(temporary, "wb") as output_file:
        shutil.copyfileobj(source_file, output_file)
    temporary.replace(output)
    print(f"rootfs base is ready: {output}")
    return 0


def add_rootfs_base_arguments(parser) -> None:
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--force", type=parse_bool, default=False)
