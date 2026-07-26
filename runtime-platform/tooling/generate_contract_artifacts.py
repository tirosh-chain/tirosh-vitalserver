#!/usr/bin/env python3
"""Generate checked-in contract artifacts from canonical JSON Schema and OpenAPI sources."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Optional, Sequence

from tooling.contracts import (
    ContractRepository,
    ContractToolError,
    extend_baseline,
    generate_baseline,
    generate_openapi_bundle,
    replace_baseline_for_unreleased_contracts,
)


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="runtime-platform root containing canonical contracts",
    )
    baseline_group = parser.add_mutually_exclusive_group()
    baseline_group.add_argument(
        "--initialize-baseline",
        action="store_true",
        help="write the initial v1 compatibility baseline only when it does not exist",
    )
    baseline_group.add_argument(
        "--extend-baseline",
        action="store_true",
        help="record additive v1 contracts after verifying existing v1 compatibility",
    )
    baseline_group.add_argument(
        "--replace-baseline-for-unreleased-contracts",
        action="store_true",
        help="replace v1 compatibility history only for intentionally unreleased contract redesign",
    )
    arguments = parser.parse_args(argv)

    repository = ContractRepository(arguments.root)
    try:
        repository.load()
        generate_openapi_bundle(repository)
        if arguments.initialize_baseline:
            generate_baseline(repository)
        if arguments.extend_baseline:
            extend_baseline(repository)
        if arguments.replace_baseline_for_unreleased_contracts:
            replace_baseline_for_unreleased_contracts(repository)
    except ContractToolError as error:
        parser.exit(2, "contract artifact generation failed: {0}\n".format(error))
    print("runtime-platform contract artifacts generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
