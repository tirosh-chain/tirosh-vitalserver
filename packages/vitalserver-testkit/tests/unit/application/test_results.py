from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.testkit.application.metrics import (
    transfer_total_bytes_sent,
    transfer_total_requests,
)
from tirosh_vitalserver.testkit.application.results import (
    RealtimeSendResult,
    TransferSummary,
)
from tirosh_vitalserver.testkit.domain.recorder import RecorderRoom
from tirosh_vitalserver.testkit.domain.vital_file import PayloadFile


def test_value_objects_and_results_are_importable() -> None:
    payload = PayloadFile(path=Path("DEMO_260509_120000.vital"), size_bytes=128)
    room = RecorderRoom(
        payload_key="recorder-code",
        room_name="BED01",
        bed_id="bed-id",
    )

    summary = TransferSummary(
        results=(
            RealtimeSendResult(
                bytes_sent=payload.size_bytes,
                attempt=0,
                elapsed_seconds=0.01,
            ),
        ),
        elapsed_seconds=0.5,
    )

    assert room.room_name == "BED01"
    assert transfer_total_requests(summary) == 1
    assert transfer_total_bytes_sent(summary) == 128
