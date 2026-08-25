#!/usr/bin/env python3
"""Installed Recorder observability proof.

Reuses scripts/recorder_observability_compose_e2e.py to admit certified
Recorder observability NDJSON through an explicit installed admission endpoint
and query the installed Guest Control /runtime/vitaldb paths with
queryOwner=guest-control. Never starts Compose.

Requires an explicit admission base URL, an explicit Guest Control base URL,
and an exact operator mutation confirmation YES. Endpoints are never inferred
from logs, files, or absence, and no installed evidence is claimed unless
those explicit inputs are supplied. Unset/empty and invalid nonempty inputs
stay distinct diagnostics, and no certified NDJSON is posted before operator
confirmation.
"""

from __future__ import annotations

import argparse
import sys
import time
from collections.abc import Callable
from datetime import datetime
from urllib.parse import urlsplit

from scripts import recorder_observability_compose_e2e as e2e

CONFIRMATION_REQUIRED = "YES"
CONFIRMATION_MISSING = "missing"
CONFIRMATION_CONFIRMED = "confirmed"
CONFIRMATION_INVALID = "invalid"


class InstalledProofError(RuntimeError):
    """Explicit installed-proof input contract failure."""


def require_installed_endpoint(value: str | None, *, name: str) -> str:
    if value is None or value.strip() == "":
        raise InstalledProofError(
            f"{name} is missing; installed proof requires an explicit {name}"
        )
    candidate = value.strip()
    parts = urlsplit(candidate)
    if parts.scheme not in {"http", "https"} or not parts.netloc:
        raise InstalledProofError(
            f"{name} is invalid; expected an explicit http(s) base URL"
        )
    return candidate


def confirmation_status(value: str | None) -> str:
    if value is None or value.strip() == "":
        return CONFIRMATION_MISSING
    if value == CONFIRMATION_REQUIRED:
        return CONFIRMATION_CONFIRMED
    return CONFIRMATION_INVALID


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Prove certified Recorder observability NDJSON against an already "
            "installed product through an explicit admission endpoint and an "
            "explicit Guest Control /runtime/vitaldb query endpoint. Never "
            "starts Compose and never infers endpoints. Requires operator "
            "confirmation YES before any certified NDJSON is posted."
        )
    )
    parser.add_argument("--admission-base-url")
    parser.add_argument("--guest-control-base-url")
    parser.add_argument("--confirmation")
    parser.add_argument("--vrcode")
    parser.add_argument("--testdata", default=str(e2e.DEFAULT_TESTDATA))
    parser.add_argument(
        "--request-timeout",
        type=float,
        default=e2e.DEFAULT_REQUEST_TIMEOUT_SECONDS,
    )
    parser.add_argument("--projection-timeout", type=float, default=30.0)
    parser.add_argument("--projection-interval", type=float, default=0.25)
    return parser.parse_args(argv)


def main(
    argv: list[str] | None = None,
    *,
    http: e2e.HttpClient | None = None,
    commands: e2e.CommandRunner | None = None,
    sleep: Callable[[float], None] = time.sleep,
    monotonic: Callable[[], float] = time.monotonic,
    clock: Callable[[], datetime] | None = None,
) -> int:
    args = parse_args(argv)
    admission = require_installed_endpoint(
        args.admission_base_url, name="admission base URL"
    )
    guest_control = require_installed_endpoint(
        args.guest_control_base_url, name="Guest Control base URL"
    )
    status = confirmation_status(args.confirmation)
    if status == CONFIRMATION_MISSING:
        raise InstalledProofError(
            "operator mutation confirmation is missing; refusing to POST "
            "certified NDJSON"
        )
    if status == CONFIRMATION_INVALID:
        raise InstalledProofError(
            "operator mutation confirmation is invalid; expected exact value "
            f"{CONFIRMATION_REQUIRED}"
        )
    proof_argv = [
        "--ingress-base-url",
        admission,
        "--query-owner",
        "guest-control",
        "--query-base-url",
        guest_control,
        "--testdata",
        args.testdata,
        "--request-timeout",
        str(args.request_timeout),
        "--projection-timeout",
        str(args.projection_timeout),
        "--projection-interval",
        str(args.projection_interval),
    ]
    if args.vrcode:
        proof_argv += ["--vrcode", args.vrcode]
    return e2e.main(
        proof_argv,
        http=http,
        commands=commands,
        sleep=sleep,
        monotonic=monotonic,
        clock=clock,
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (InstalledProofError, e2e.ProofError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error
