#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "packages/vitalserver-devtools/src"))

from tirosh_vitalserver.devtools.runtime_v2_conformance import (  # noqa: E402
    RuntimeV2ConformanceSuite,
    http_json_getter,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a VitalServer v2 Platform/Runtime API implementation."
    )
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--platform-only", action="store_true")
    parser.add_argument("--runtime-only", action="store_true")
    parser.add_argument(
        "--token-env",
        default="VITALSERVER_RUNTIME_CONTROL_TOKEN",
        help="Environment variable containing an optional bearer token.",
    )
    args = parser.parse_args()
    if args.platform_only and args.runtime_only:
        parser.error("--platform-only and --runtime-only are mutually exclusive")

    report = RuntimeV2ConformanceSuite(
        http_json_getter(
            base_url=args.base_url,
            timeout_seconds=args.timeout,
            bearer_token=os.environ.get(args.token_env),
        )
    ).run(platform=not args.runtime_only, runtime=not args.platform_only)

    for resource in report.checked_resources:
        print(f"checked {resource}")
    for issue in report.issues:
        print(f"failed {issue.resource}: {issue.message}")
    if report.passed:
        print("Runtime v2 conformance passed")
        return 0
    print(f"Runtime v2 conformance failed: {len(report.issues)} issue(s)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
