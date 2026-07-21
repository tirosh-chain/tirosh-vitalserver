"""Pure contracts for probing versioned `.vital` file headers."""

from __future__ import annotations

import math
import struct
from dataclasses import dataclass
from enum import IntEnum

from tirosh_vitalserver.core.errors import VitalFileFormatError

VITAL_MAGIC = b"VITA"
VITAL_HEADER_PREFIX_LENGTH = 10
VITAL_BASE_HEADER_LENGTH = 10
VITAL_TIMED_HEADER_LENGTH = 26
VITAL_PACKED_HEADER_LENGTH = 27


class VitalFileFormatVersion(IntEnum):
    """Supported `.vital` wire format versions."""

    V1 = 1
    V2 = 2
    V3 = 3

    @classmethod
    def from_code(cls, code: int) -> VitalFileFormatVersion:
        """Decode a supported wire version without accepting future versions."""

        try:
            return cls(code)
        except ValueError as error:
            raise VitalFileFormatError(
                code="unsupportedFormatVersion",
                detail=f"unsupported .vital format version {code}",
            ) from error


class VitalTrackKind(IntEnum):
    """Track kinds defined by the `.vital` wire contract."""

    WAVEFORM = 1
    NUMERIC = 2
    STRING = 5

    @classmethod
    def from_code(cls, code: object) -> VitalTrackKind:
        """Decode a supported track kind without inferring it from metadata."""

        if isinstance(code, bool) or not isinstance(code, int):
            raise VitalFileFormatError(
                code="unsupportedTrackType",
                detail=f"unsupported .vital track type {code!r}",
            )
        try:
            return cls(code)
        except ValueError as error:
            raise VitalFileFormatError(
                code="unsupportedTrackType",
                detail=f"unsupported .vital track type {code}",
            ) from error


@dataclass(frozen=True)
class VitalFileHeader:
    """Version-aware header values decoded from one `.vital` byte stream."""

    format_version: VitalFileFormatVersion
    header_length: int
    timezone_bias: int
    instance_id: int
    program_version: tuple[int, int, int, int]
    started_at: float | None
    ended_at: float | None
    packed: bool | None
    extension_bytes: bytes

    @property
    def body_offset(self) -> int:
        """Return the first packet offset in the decompressed stream."""

        return VITAL_HEADER_PREFIX_LENGTH + self.header_length


def probe_vital_header(payload: bytes) -> VitalFileHeader:
    """Decode a complete `.vital` header from decompressed leading bytes."""

    if len(payload) < VITAL_HEADER_PREFIX_LENGTH:
        raise VitalFileFormatError(
            code="truncatedHeader",
            detail=(f".vital header prefix requires 10 bytes; received {len(payload)}"),
        )
    if payload[:4] != VITAL_MAGIC:
        raise VitalFileFormatError(
            code="invalidMagic",
            detail=".vital stream must begin with VITA",
        )

    version_code = int.from_bytes(payload[4:8], byteorder="little")
    format_version = VitalFileFormatVersion.from_code(version_code)
    header_length = int.from_bytes(payload[8:10], byteorder="little")
    if header_length < VITAL_BASE_HEADER_LENGTH:
        raise VitalFileFormatError(
            code="invalidHeaderLength",
            detail=(
                ".vital header length must include the 10-byte base header; "
                f"received {header_length}"
            ),
        )

    body_offset = VITAL_HEADER_PREFIX_LENGTH + header_length
    if len(payload) < body_offset:
        raise VitalFileFormatError(
            code="truncatedHeader",
            detail=(
                f".vital header declares {header_length} body bytes; "
                f"received {len(payload) - VITAL_HEADER_PREFIX_LENGTH}"
            ),
        )

    timezone_bias = struct.unpack_from("<h", payload, 10)[0]
    instance_id = struct.unpack_from("<I", payload, 12)[0]
    program_version = tuple(payload[16:20])

    started_at: float | None = None
    ended_at: float | None = None
    packed: bool | None = None
    known_header_length = VITAL_BASE_HEADER_LENGTH

    if header_length >= VITAL_TIMED_HEADER_LENGTH:
        started_at = struct.unpack_from("<d", payload, 20)[0]
        ended_at = struct.unpack_from("<d", payload, 28)[0]
        if not math.isfinite(started_at) or not math.isfinite(ended_at):
            raise VitalFileFormatError(
                code="invalidHeaderTime",
                detail=".vital header timestamps must be finite",
            )
        known_header_length = VITAL_TIMED_HEADER_LENGTH

    if header_length >= VITAL_PACKED_HEADER_LENGTH:
        packed_code = payload[36]
        if packed_code not in (0, 1):
            raise VitalFileFormatError(
                code="invalidPackedFlag",
                detail=f".vital packed flag must be 0 or 1; received {packed_code}",
            )
        packed = packed_code == 1
        known_header_length = VITAL_PACKED_HEADER_LENGTH

    return VitalFileHeader(
        format_version=format_version,
        header_length=header_length,
        timezone_bias=timezone_bias,
        instance_id=instance_id,
        program_version=(
            program_version[0],
            program_version[1],
            program_version[2],
            program_version[3],
        ),
        started_at=started_at,
        ended_at=ended_at,
        packed=packed,
        extension_bytes=payload[
            VITAL_HEADER_PREFIX_LENGTH + known_header_length : body_offset
        ],
    )
