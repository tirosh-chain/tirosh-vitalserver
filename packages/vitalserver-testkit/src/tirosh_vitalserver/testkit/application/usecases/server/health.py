"""Helpers for managing a local VitalServer test target."""

from __future__ import annotations

import time

from tirosh_vitalserver.testkit.application.ports import VitalServerPort


def wait_for_server(
    client: VitalServerPort,
    *,
    path: str = "/check",
    timeout_seconds: float = 60.0,
    interval_seconds: float = 1.0,
) -> None:
    """Wait until VitalServer returns a non-5xx health response."""

    deadline = time.monotonic() + timeout_seconds
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            response = client.health(path)
            if response.status_code < 500:
                return
        except Exception as exc:
            last_error = exc
        time.sleep(interval_seconds)

    detail = f" last error: {last_error}" if last_error else ""
    raise TimeoutError(
        f"VitalServer did not become ready within {timeout_seconds} seconds.{detail}"
    )
