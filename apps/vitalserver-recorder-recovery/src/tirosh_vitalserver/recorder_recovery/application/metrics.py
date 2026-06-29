"""Metrics for VitalServer `.vital` recovery uploads."""

from __future__ import annotations

from tirosh_vitalserver.recorder_recovery.application.results import TransferSummary


def transfer_total_requests(summary: TransferSummary) -> int:
    """Return the number of attempted upload requests."""

    return len(summary.results)


def transfer_failed_requests(summary: TransferSummary) -> int:
    """Return upload requests that failed by exception or HTTP status."""

    return sum(
        1
        for result in summary.results
        if result.error is not None or result.response.status_code >= 400
    )


def transfer_successful_requests(summary: TransferSummary) -> int:
    """Return upload requests that completed with a non-error HTTP status."""

    return transfer_total_requests(summary) - transfer_failed_requests(summary)
