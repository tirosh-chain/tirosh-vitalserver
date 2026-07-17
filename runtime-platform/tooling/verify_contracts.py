#!/usr/bin/env python3
"""Run the runtime-platform contract kernel verification suite."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Optional, Sequence

from tooling.contracts import ContractRepository, verify_all


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="runtime-platform root to validate",
    )
    arguments = parser.parse_args(argv)
    repository = ContractRepository(arguments.root)
    findings = verify_all(repository)
    if not findings:
        print("runtime-platform contract verification passed")
        return 0
    print("runtime-platform contract verification failed:")
    for finding in findings:
        print("  {0}".format(finding.render()))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
