from __future__ import annotations

import pytest

from tirosh_vitalserver.testkit.application.assertions import assert_transfer_success
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
    RealtimeSendResult,
    RealtimeStreamResult,
    StreamSummary,
    TransferSummary,
)


def test_transfer_metrics_are_derived_from_result_values() -> None:
    summary = TransferSummary(
        results=(
            RealtimeSendResult(bytes_sent=100, attempt=0, elapsed_seconds=0.01),
            RealtimeSendResult(
                bytes_sent=50,
                attempt=1,
                elapsed_seconds=0.01,
                error="boom",
            ),
        ),
        elapsed_seconds=0.5,
    )

    assert transfer_total_requests(summary) == 2
    assert transfer_successful_requests(summary) == 1
    assert transfer_failed_requests(summary) == 1
    assert transfer_total_bytes_sent(summary) == 150
    assert transfer_bytes_per_second(summary) == 300


def test_stream_metrics_are_derived_from_stream_values() -> None:
    summary = StreamSummary(
        results=(
            RealtimeStreamResult(
                messages_sent=3,
                bytes_sent=120,
                elapsed_seconds=0.5,
            ),
            RealtimeStreamResult(
                messages_sent=1,
                bytes_sent=40,
                elapsed_seconds=0.5,
                error="boom",
            ),
        ),
        elapsed_seconds=2,
    )

    assert stream_total_streams(summary) == 2
    assert stream_successful_streams(summary) == 1
    assert stream_failed_streams(summary) == 1
    assert stream_total_messages_sent(summary) == 4
    assert stream_total_bytes_sent(summary) == 160
    assert stream_bytes_per_second(summary) == 80


def test_assert_transfer_success_allows_configured_failure_rate() -> None:
    summary = TransferSummary(
        results=(
            RealtimeSendResult(bytes_sent=100, attempt=0, elapsed_seconds=0.01),
            RealtimeSendResult(
                bytes_sent=50,
                attempt=1,
                elapsed_seconds=0.01,
                error="boom",
            ),
        ),
        elapsed_seconds=0.5,
    )

    assert_transfer_success(summary, max_failure_rate=0.5)


def test_assert_transfer_success_rejects_empty_summary() -> None:
    with pytest.raises(AssertionError, match="no transfer requests"):
        assert_transfer_success(TransferSummary(results=(), elapsed_seconds=0))
