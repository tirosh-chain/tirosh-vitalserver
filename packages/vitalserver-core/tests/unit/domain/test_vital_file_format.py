from __future__ import annotations

import math
import struct

import pytest

from tirosh_vitalserver.core.domain.vital_file import (
    VitalFileFormatError,
    VitalFileFormatVersion,
    VitalServerMonitorType,
    VitalTrackKind,
    probe_vital_header,
)


def test_vitalserver_monitor_types_match_upstream_wire_ids() -> None:
    assert VitalServerMonitorType(8).name == "PLETH_WAV"
    assert VitalServerMonitorType(12).name == "RESP_RR"
    assert VitalServerMonitorType(14).name == "CO2_RR"
    assert VitalServerMonitorType(21).name == "CVP_CVP"
    assert VitalServerMonitorType(85).name == "TOF_RATIO"
    assert VitalServerMonitorType["PLETH_SPO2"].value == 10
    assert VitalServerMonitorType["CO2_RR"].value == 14


def test_vitalserver_monitor_type_preserves_unknown_as_absent() -> None:
    assert VitalServerMonitorType.from_id(0) is None
    assert VitalServerMonitorType.from_wire_name("HCT") is None


@pytest.mark.parametrize(
    "version",
    (VitalFileFormatVersion.V1, VitalFileFormatVersion.V2),
)
def test_probe_vital_header_supports_legacy_base_headers(
    version: VitalFileFormatVersion,
) -> None:
    payload = vital_header(version=version, header_body=base_header())

    header = probe_vital_header(payload)

    assert header.format_version is version
    assert header.header_length == 10
    assert header.timezone_bias == -540
    assert header.instance_id == 42
    assert header.program_version == (1, 2, 3, 4)
    assert header.started_at is None
    assert header.ended_at is None
    assert header.packed is None
    assert header.extension_bytes == b""
    assert header.body_offset == 20


def test_probe_vital_header_decodes_current_timed_packed_header() -> None:
    payload = vital_header(
        version=VitalFileFormatVersion.V3,
        header_body=(
            base_header() + struct.pack("<ddB", 1784600000.25, 1784600600.75, 1)
        ),
    )

    header = probe_vital_header(payload)

    assert header.format_version is VitalFileFormatVersion.V3
    assert header.header_length == 27
    assert header.started_at == 1784600000.25
    assert header.ended_at == 1784600600.75
    assert header.packed is True
    assert header.extension_bytes == b""
    assert header.body_offset == 37


def test_probe_vital_header_preserves_unknown_extension_bytes() -> None:
    payload = vital_header(
        version=VitalFileFormatVersion.V3,
        header_body=base_header() + struct.pack("<ddB", 1.0, 2.0, 0) + b"ext",
    )

    header = probe_vital_header(payload)

    assert header.header_length == 30
    assert header.packed is False
    assert header.extension_bytes == b"ext"
    assert header.body_offset == 40


@pytest.mark.parametrize(
    ("payload", "code"),
    [
        (b"", "truncatedHeader"),
        (b"NOPE" + bytes(6), "invalidMagic"),
        (
            b"VITA" + (0).to_bytes(4, "little") + (10).to_bytes(2, "little"),
            "unsupportedFormatVersion",
        ),
        (
            b"VITA" + (4).to_bytes(4, "little") + (10).to_bytes(2, "little"),
            "unsupportedFormatVersion",
        ),
        (
            b"VITA" + (3).to_bytes(4, "little") + (9).to_bytes(2, "little"),
            "invalidHeaderLength",
        ),
        (
            b"VITA" + (3).to_bytes(4, "little") + (27).to_bytes(2, "little"),
            "truncatedHeader",
        ),
    ],
)
def test_probe_vital_header_rejects_invalid_contracts(
    payload: bytes,
    code: str,
) -> None:
    with pytest.raises(VitalFileFormatError) as error:
        probe_vital_header(payload)

    assert error.value.code == code


@pytest.mark.parametrize("value", (math.nan, math.inf, -math.inf))
def test_probe_vital_header_rejects_non_finite_times(value: float) -> None:
    payload = vital_header(
        version=VitalFileFormatVersion.V3,
        header_body=base_header() + struct.pack("<dd", value, 2.0),
    )

    with pytest.raises(VitalFileFormatError) as error:
        probe_vital_header(payload)

    assert error.value.code == "invalidHeaderTime"


def test_probe_vital_header_rejects_invalid_packed_flag() -> None:
    payload = vital_header(
        version=VitalFileFormatVersion.V3,
        header_body=base_header() + struct.pack("<ddB", 1.0, 2.0, 2),
    )

    with pytest.raises(VitalFileFormatError) as error:
        probe_vital_header(payload)

    assert error.value.code == "invalidPackedFlag"


@pytest.mark.parametrize(
    ("code", "kind"),
    [
        (1, VitalTrackKind.WAVEFORM),
        (2, VitalTrackKind.NUMERIC),
        (5, VitalTrackKind.STRING),
    ],
)
def test_vital_track_kind_decodes_explicit_wire_type(
    code: int,
    kind: VitalTrackKind,
) -> None:
    assert VitalTrackKind.from_code(code) is kind


@pytest.mark.parametrize("code", (0, 3, 4, 6, True, None, "1"))
def test_vital_track_kind_rejects_unknown_wire_type(code: object) -> None:
    with pytest.raises(VitalFileFormatError) as error:
        VitalTrackKind.from_code(code)

    assert error.value.code == "unsupportedTrackType"


def base_header() -> bytes:
    return struct.pack("<hI4B", -540, 42, 1, 2, 3, 4)


def vital_header(
    *,
    version: VitalFileFormatVersion,
    header_body: bytes,
) -> bytes:
    return (
        b"VITA"
        + int(version).to_bytes(4, "little")
        + len(header_body).to_bytes(2, "little")
        + header_body
    )
