#!/usr/bin/env python3
"""Create a verified, target-specific Guest Tools wheelhouse for a release."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packages/vitalserver-devtools/src"))

from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (  # noqa: E402
    GUEST_RUNTIME_TARGETS,
    stage_guest_python_wheelhouse,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stage a pinned, hash-verified Guest Tools wheelhouse."
    )
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--target",
        choices=sorted(GUEST_RUNTIME_TARGETS),
        default="linux-amd64",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project = args.project.resolve()
    output = args.output.resolve()
    if not (project / "pyproject.toml").is_file():
        raise SystemExit(f"Guest Tools project metadata is missing: {project}")
    if output.exists():
        raise SystemExit(
            "Guest Tools wheelhouse output already exists; refuse to merge release "
            f"artifacts: {output}"
        )
    stage_guest_python_wheelhouse(project, output, targets=(args.target,))
    print(f"Guest Tools wheelhouse staged: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
