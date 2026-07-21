from __future__ import annotations

from tirosh_vitalserver.core.domain.vital_file import (
    VitalTrackDefinition,
    VitalTrackKind,
)
from tirosh_vitalserver.testkit.adapters.outbound.real_vital import track_header


def test_track_header_preserves_explicit_one_hertz_waveform_kind() -> None:
    header = track_header(source_track(track_type=1, sample_rate=1.0))

    assert header.kind is VitalTrackKind.WAVEFORM
    assert header.srate == 1.0


def test_track_header_preserves_zero_rate_numeric_kind() -> None:
    header = track_header(source_track(track_type=2, sample_rate=0.0))

    assert header.kind is VitalTrackKind.NUMERIC
    assert header.srate == 0.0


def test_track_header_preserves_string_kind() -> None:
    header = track_header(source_track(track_type=5, sample_rate=0.0))

    assert header.kind is VitalTrackKind.STRING


def source_track(*, track_type: int, sample_rate: float) -> VitalTrackDefinition:
    return VitalTrackDefinition(
        dtname="Source/Track",
        device_name="Source",
        name="Track",
        kind=VitalTrackKind.from_code(track_type),
        format_code=1,
        unit="",
        sample_rate=sample_rate,
        minimum_display=0.0,
        maximum_display=100.0,
        color=0,
        gain=1.0,
        offset=0.0,
        monitor_type_id=0,
    )
