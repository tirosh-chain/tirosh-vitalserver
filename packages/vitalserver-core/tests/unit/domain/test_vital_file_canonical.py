from __future__ import annotations

import pytest

from tirosh_vitalserver.core.domain.vital_file import (
    VitalDeviceDefinition,
    VitalFileFormatError,
    VitalFileFormatVersion,
    VitalFileHeader,
    VitalFileManifest,
    VitalTrackDefinition,
    VitalTrackKind,
)


def test_manifest_preserves_explicit_track_kinds_without_rate_inference() -> None:
    waveform = track(kind=VitalTrackKind.WAVEFORM, sample_rate=1.0, name="WAVE")
    numeric = track(kind=VitalTrackKind.NUMERIC, sample_rate=0.0, name="HR")
    string = track(kind=VitalTrackKind.STRING, sample_rate=0.0, name="LABEL")

    manifest = VitalFileManifest(
        header=header(),
        started_at=100.0,
        ended_at=102.0,
        devices=(VitalDeviceDefinition(name="Source", device_type="monitor", port=""),),
        tracks=(waveform, numeric, string),
    )

    assert manifest.duration_seconds == 2.0
    assert manifest.track("Source/WAVE").kind is VitalTrackKind.WAVEFORM
    assert manifest.track("Source/HR").kind is VitalTrackKind.NUMERIC
    assert manifest.track("Source/LABEL").kind is VitalTrackKind.STRING


@pytest.mark.parametrize(
    ("kind", "sample_rate"),
    [
        (VitalTrackKind.WAVEFORM, 0.0),
        (VitalTrackKind.NUMERIC, -1.0),
        (VitalTrackKind.STRING, float("nan")),
    ],
)
def test_track_definition_rejects_invalid_metadata(
    kind: VitalTrackKind,
    sample_rate: float,
) -> None:
    with pytest.raises(VitalFileFormatError) as error:
        track(kind=kind, sample_rate=sample_rate, name="INVALID")

    expected_code = (
        "invalidWaveformSampleRate"
        if kind is VitalTrackKind.WAVEFORM
        else "invalidTrackMetadata"
    )
    assert error.value.code == expected_code


def test_manifest_rejects_reversed_time_range() -> None:
    with pytest.raises(VitalFileFormatError) as error:
        VitalFileManifest(
            header=header(),
            started_at=102.0,
            ended_at=100.0,
            devices=(),
            tracks=(
                track(
                    kind=VitalTrackKind.NUMERIC,
                    sample_rate=0.0,
                    name="HR",
                ),
            ),
        )

    assert error.value.code == "invalidFileMetadata"


def test_manifest_reports_missing_track_explicitly() -> None:
    manifest = VitalFileManifest(
        header=header(),
        started_at=100.0,
        ended_at=101.0,
        devices=(),
        tracks=(track(kind=VitalTrackKind.NUMERIC, sample_rate=0.0, name="HR"),),
    )

    with pytest.raises(VitalFileFormatError) as error:
        manifest.track("Source/SPO2")

    assert error.value.code == "trackNotFound"


def header() -> VitalFileHeader:
    return VitalFileHeader(
        format_version=VitalFileFormatVersion.V3,
        header_length=27,
        timezone_bias=-540,
        instance_id=0,
        program_version=(0, 0, 0, 0),
        started_at=100.0,
        ended_at=102.0,
        packed=True,
        extension_bytes=b"",
    )


def track(
    *,
    kind: VitalTrackKind,
    sample_rate: float,
    name: str,
) -> VitalTrackDefinition:
    return VitalTrackDefinition(
        dtname=f"Source/{name}",
        name=name,
        device_name="Source",
        kind=kind,
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
