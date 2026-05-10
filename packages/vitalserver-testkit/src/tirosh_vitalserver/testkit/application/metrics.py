"""Derived metrics for transfer and visibility results."""

from __future__ import annotations

from tirosh_vitalserver.testkit.application.results import (
    RealtimeSendResult,
    RealtimeStreamResult,
    RecorderSendResult,
    RecorderVisibilityResult,
    StreamSummary,
    TransferSummary,
    UploadResult,
)

TransferResult = UploadResult | RecorderSendResult | RealtimeSendResult


def transfer_result_ok(result: TransferResult) -> bool:
    """Return whether one finite transfer finished successfully."""

    if isinstance(result, RealtimeSendResult):
        return result.error is None

    return result.error is None and result.response.ok


def recorder_visibility_result_visible(result: RecorderVisibilityResult) -> bool:
    """Return whether VitalServer exposes non-empty metadata for one room."""

    body = result.response.text.strip()

    return result.response.ok and body not in {"", "{}", "[]", "null"}


def transfer_total_requests(summary: TransferSummary) -> int:
    """Return the number of request-like transfer results."""

    return len(summary.results)


def transfer_successful_requests(summary: TransferSummary) -> int:
    """Return the number of successful request-like transfer results."""

    return sum(1 for result in summary.results if transfer_result_ok(result))


def transfer_failed_requests(summary: TransferSummary) -> int:
    """Return the number of failed request-like transfer results."""

    return transfer_total_requests(summary) - transfer_successful_requests(summary)


def transfer_total_bytes_sent(summary: TransferSummary) -> int:
    """Return the total encoded bytes sent by finite transfers."""

    return sum(result.bytes_sent for result in summary.results)


def transfer_bytes_per_second(summary: TransferSummary) -> float:
    """Return finite transfer throughput in bytes per second."""

    if summary.elapsed_seconds == 0:
        return 0.0

    return transfer_total_bytes_sent(summary) / summary.elapsed_seconds


def stream_result_ok(result: RealtimeStreamResult) -> bool:
    """Return whether one persistent stream finished successfully."""

    return result.error is None


def stream_total_streams(summary: StreamSummary) -> int:
    """Return the number of stream workers."""

    return len(summary.results)


def stream_successful_streams(summary: StreamSummary) -> int:
    """Return the number of successful stream workers."""

    return sum(1 for result in summary.results if stream_result_ok(result))


def stream_failed_streams(summary: StreamSummary) -> int:
    """Return the number of failed stream workers."""

    return stream_total_streams(summary) - stream_successful_streams(summary)


def stream_total_messages_sent(summary: StreamSummary) -> int:
    """Return the total Socket.IO messages sent by all streams."""

    return sum(result.messages_sent for result in summary.results)


def stream_total_bytes_sent(summary: StreamSummary) -> int:
    """Return the total encoded bytes sent by all streams."""

    return sum(result.bytes_sent for result in summary.results)


def stream_bytes_per_second(summary: StreamSummary) -> float:
    """Return streaming throughput in bytes per second."""

    if summary.elapsed_seconds == 0:
        return 0.0

    return stream_total_bytes_sent(summary) / summary.elapsed_seconds
