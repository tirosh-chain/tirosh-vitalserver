"""Assertions for product `.vital` recovery transfer results."""

from __future__ import annotations

from tirosh_vitalserver.recorder_recovery.application.metrics import (
    transfer_failed_requests,
    transfer_total_requests,
)
from tirosh_vitalserver.recorder_recovery.application.results import TransferSummary


def assert_transfer_success(
    summary: TransferSummary, *, max_failure_rate: float = 0.0
) -> None:
    """Assert that an upload recovery stayed within the allowed failure rate."""

    total_requests = transfer_total_requests(summary)
    failed_requests = transfer_failed_requests(summary)

    if total_requests == 0:
        raise AssertionError("no transfer requests were executed")

    failure_rate = failed_requests / total_requests

    if failure_rate > max_failure_rate:
        message = (
            f"transfer failure rate {failure_rate:.2%} exceeded "
            f"{max_failure_rate:.2%}; "
            f"{failed_requests}/{total_requests} requests failed"
        )
        raise AssertionError(message)
