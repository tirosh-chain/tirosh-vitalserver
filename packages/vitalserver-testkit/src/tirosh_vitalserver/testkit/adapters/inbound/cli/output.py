"""CLI output helpers."""

from __future__ import annotations

from tirosh_vitalserver.testkit.application.metrics import (
    stream_bytes_per_second,
    stream_failed_streams,
    stream_successful_streams,
    stream_total_bytes_sent,
    stream_total_messages_sent,
    stream_total_streams,
    transfer_bytes_per_second,
    transfer_failed_requests,
    transfer_successful_requests,
    transfer_total_bytes_sent,
    transfer_total_requests,
)
from tirosh_vitalserver.testkit.application.results import (
    StreamSummary,
    TransferSummary,
)


def print_summary(summary: TransferSummary) -> None:
    """Print request-based transfer metrics in a script-friendly format."""

    print(f"requests: {transfer_total_requests(summary)}")
    print(f"success: {transfer_successful_requests(summary)}")
    print(f"failed: {transfer_failed_requests(summary)}")
    print(f"elapsed_seconds: {summary.elapsed_seconds:.3f}")
    print(f"bytes_sent: {transfer_total_bytes_sent(summary)}")
    print(f"bytes_per_second: {transfer_bytes_per_second(summary):.2f}")


def print_stream_summary(summary: StreamSummary) -> None:
    """Print persistent streaming metrics in a script-friendly format."""

    print(f"streams: {stream_total_streams(summary)}")
    print(f"success: {stream_successful_streams(summary)}")
    print(f"failed: {stream_failed_streams(summary)}")
    print(f"messages_sent: {stream_total_messages_sent(summary)}")
    print(f"elapsed_seconds: {summary.elapsed_seconds:.3f}")
    print(f"bytes_sent: {stream_total_bytes_sent(summary)}")
    print(f"bytes_per_second: {stream_bytes_per_second(summary):.2f}")
