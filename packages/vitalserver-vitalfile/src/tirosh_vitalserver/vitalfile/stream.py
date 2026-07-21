"""Bounded-memory packet scanner for supported Vital File versions."""

from __future__ import annotations

import gzip
import math
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from tirosh_vitalserver.core.domain.vital_file import (
    VITAL_HEADER_PREFIX_LENGTH,
    VitalDeviceDefinition,
    VitalFileFormatError,
    VitalFileHeader,
    VitalTrackDefinition,
    VitalTrackKind,
    probe_vital_header,
)

from .reader import VitalFileReadError

PACKET_HEADER_BYTES = 5
STREAM_CHUNK_BYTES = 64 * 1024
MAX_METADATA_PACKET_BYTES = 1024 * 1024

_FORMAT_STRUCTS: dict[int, struct.Struct] = {
    1: struct.Struct("<f"),
    2: struct.Struct("<d"),
    3: struct.Struct("<b"),
    4: struct.Struct("<B"),
    5: struct.Struct("<h"),
    6: struct.Struct("<H"),
    7: struct.Struct("<l"),
    8: struct.Struct("<L"),
}


class VitalFilePacketSink(Protocol):
    """Consume explicit metadata and bounded record chunks from one file."""

    def on_header(self, header: VitalFileHeader) -> None: ...

    def on_device(self, *, device_id: int, device: VitalDeviceDefinition) -> None: ...

    def on_track(self, *, track_id: int, track: VitalTrackDefinition) -> None: ...

    def on_waveform_chunk(
        self,
        *,
        track_id: int,
        recorded_at: float,
        sample_offset: int,
        sample_count: int,
        raw_values: bytes,
    ) -> None: ...

    def on_numeric_record(
        self,
        *,
        track_id: int,
        recorded_at: float,
        value: float,
    ) -> None: ...

    def on_string_record(
        self,
        *,
        track_id: int,
        recorded_at: float,
        value: str,
    ) -> None: ...


class _ReadableStream(Protocol):
    def read(self, size: int = -1) -> bytes: ...


@dataclass(frozen=True, slots=True)
class _TrackWireDefinition:
    definition: VitalTrackDefinition
    value_struct: struct.Struct | None


class VitalFilePacketScanner:
    """Scan one gzip Vital File without allocating a record-sized buffer."""

    def scan(self, path: Path, sink: VitalFilePacketSink) -> VitalFileHeader:
        if path.suffix.lower() != ".vital" or not path.is_file():
            raise VitalFileReadError(
                code="sourceUnavailable",
                detail=f"Vital File source is unavailable: {path}",
            )
        try:
            with gzip.open(path, "rb") as stream:
                header = self._read_header(stream)
                sink.on_header(header)
                self._scan_packets(stream, sink)
                return header
        except (VitalFileFormatError, VitalFileReadError):
            raise
        except (EOFError, gzip.BadGzipFile, OSError) as error:
            raise VitalFileReadError(
                code="decodeFailed",
                detail=f"Vital File gzip decode failed: {path.name}: {error}",
            ) from error

    @staticmethod
    def _read_header(stream: _ReadableStream) -> VitalFileHeader:
        prefix = _read_exact(stream, VITAL_HEADER_PREFIX_LENGTH, code="truncatedHeader")
        header_length = int.from_bytes(prefix[8:10], byteorder="little")
        header_body = _read_exact(stream, header_length, code="truncatedHeader")
        return probe_vital_header(prefix + header_body)

    def _scan_packets(
        self,
        stream: _ReadableStream,
        sink: VitalFilePacketSink,
    ) -> None:
        devices: dict[int, VitalDeviceDefinition] = {}
        tracks: dict[int, _TrackWireDefinition] = {}
        while True:
            packet_header = _read_up_to(stream, PACKET_HEADER_BYTES)
            if not packet_header:
                return
            if len(packet_header) != PACKET_HEADER_BYTES:
                raise VitalFileReadError(
                    code="truncatedPacket",
                    detail=(
                        "Vital File packet header is truncated: "
                        f"received={len(packet_header)}"
                    ),
                )
            packet_type, packet_length = struct.unpack("<BI", packet_header)
            if packet_type == 1:
                self._scan_record(
                    stream,
                    packet_length=packet_length,
                    tracks=tracks,
                    sink=sink,
                )
                continue
            if packet_type in (0, 9):
                if packet_length > MAX_METADATA_PACKET_BYTES:
                    raise VitalFileReadError(
                        code="invalidTrackMetadata"
                        if packet_type == 0
                        else "invalidDeviceMetadata",
                        detail=(
                            "Vital File metadata packet exceeds the explicit limit: "
                            f"type={packet_type} length={packet_length} "
                            f"maximum={MAX_METADATA_PACKET_BYTES}"
                        ),
                    )
                payload = _read_exact(stream, packet_length, code="truncatedPacket")
                if packet_type == 9:
                    device_id, device = _decode_device(payload)
                    # The published format allows a later DEVINFO for the same
                    # id to replace the previous definition.
                    devices[device_id] = device
                    sink.on_device(device_id=device_id, device=device)
                else:
                    track_id, wire_track = _decode_track(payload, devices=devices)
                    if track_id in tracks:
                        raise VitalFileReadError(
                            code="invalidTrackMetadata",
                            detail=f"Vital File track id is duplicated: {track_id}",
                        )
                    tracks[track_id] = wire_track
                    sink.on_track(track_id=track_id, track=wire_track.definition)
                continue
            _discard_exact(stream, packet_length)

    def _scan_record(
        self,
        stream: _ReadableStream,
        *,
        packet_length: int,
        tracks: dict[int, _TrackWireDefinition],
        sink: VitalFilePacketSink,
    ) -> None:
        if packet_length < 12:
            _discard_exact(stream, packet_length)
            raise VitalFileReadError(
                code="invalidRecord",
                detail=f"Vital File record packet is too short: {packet_length}",
            )
        info_length = struct.unpack(
            "<H",
            _read_exact(stream, 2, code="truncatedPacket"),
        )[0]
        remaining = packet_length - 2
        if info_length < 10 or info_length > remaining:
            _discard_exact(stream, remaining)
            raise VitalFileReadError(
                code="invalidRecord",
                detail=(
                    "Vital File record info length is invalid: "
                    f"infoLength={info_length} packetLength={packet_length}"
                ),
            )
        info = _read_exact(stream, info_length, code="truncatedPacket")
        remaining -= info_length
        recorded_at, track_id = struct.unpack_from("<dH", info)
        if not math.isfinite(recorded_at):
            _discard_exact(stream, remaining)
            raise VitalFileReadError(
                code="invalidRecord",
                detail=f"Vital File record timestamp is not finite: trackId={track_id}",
            )
        wire_track = tracks.get(track_id)
        if wire_track is None:
            _discard_exact(stream, remaining)
            # The published Vital File contract explicitly requires records
            # with an unknown track id to be ignored.
            return
        kind = wire_track.definition.kind
        if kind is VitalTrackKind.WAVEFORM:
            self._scan_waveform_record(
                stream,
                remaining=remaining,
                recorded_at=recorded_at,
                track_id=track_id,
                value_struct=_required_value_struct(wire_track),
                sink=sink,
            )
            return
        if kind is VitalTrackKind.NUMERIC:
            value_struct = _required_value_struct(wire_track)
            if remaining != value_struct.size:
                _discard_exact(stream, remaining)
                raise VitalFileReadError(
                    code="invalidRecord",
                    detail=(
                        "Vital File numeric record length does not match its format: "
                        f"trackId={track_id} expected={value_struct.size} "
                        f"actual={remaining}"
                    ),
                )
            value = float(
                value_struct.unpack(
                    _read_exact(stream, remaining, code="truncatedPacket")
                )[0]
            )
            sink.on_numeric_record(
                track_id=track_id,
                recorded_at=recorded_at,
                value=value,
            )
            return
        self._scan_string_record(
            stream,
            remaining=remaining,
            recorded_at=recorded_at,
            track_id=track_id,
            sink=sink,
        )

    @staticmethod
    def _scan_waveform_record(
        stream: _ReadableStream,
        *,
        remaining: int,
        recorded_at: float,
        track_id: int,
        value_struct: struct.Struct,
        sink: VitalFilePacketSink,
    ) -> None:
        if remaining < 4:
            _discard_exact(stream, remaining)
            raise VitalFileReadError(
                code="invalidRecord",
                detail=(
                    f"Vital File waveform sample count is missing: trackId={track_id}"
                ),
            )
        sample_count = struct.unpack(
            "<I",
            _read_exact(stream, 4, code="truncatedPacket"),
        )[0]
        remaining -= 4
        expected = sample_count * value_struct.size
        if remaining != expected:
            _discard_exact(stream, remaining)
            raise VitalFileReadError(
                code="invalidRecord",
                detail=(
                    "Vital File waveform record length does not match its "
                    "sample count: "
                    f"trackId={track_id} expected={expected} actual={remaining}"
                ),
            )
        samples_per_chunk = max(1, STREAM_CHUNK_BYTES // value_struct.size)
        sample_offset = 0
        while sample_offset < sample_count:
            chunk_count = min(samples_per_chunk, sample_count - sample_offset)
            raw_values = _read_exact(
                stream,
                chunk_count * value_struct.size,
                code="truncatedPacket",
            )
            sink.on_waveform_chunk(
                track_id=track_id,
                recorded_at=recorded_at,
                sample_offset=sample_offset,
                sample_count=chunk_count,
                raw_values=raw_values,
            )
            sample_offset += chunk_count

    @staticmethod
    def _scan_string_record(
        stream: _ReadableStream,
        *,
        remaining: int,
        recorded_at: float,
        track_id: int,
        sink: VitalFilePacketSink,
    ) -> None:
        if remaining < 8:
            _discard_exact(stream, remaining)
            raise VitalFileReadError(
                code="invalidRecord",
                detail=f"Vital File string record is too short: trackId={track_id}",
            )
        prefix = _read_exact(stream, 8, code="truncatedPacket")
        string_length = struct.unpack_from("<I", prefix, 4)[0]
        remaining -= 8
        if remaining != string_length:
            _discard_exact(stream, remaining)
            raise VitalFileReadError(
                code="invalidRecord",
                detail=(
                    "Vital File string record length is invalid: "
                    f"trackId={track_id} declared={string_length} actual={remaining}"
                ),
            )
        encoded = _read_exact(stream, string_length, code="truncatedPacket")
        try:
            value = encoded.decode("utf-8")
        except UnicodeDecodeError as error:
            raise VitalFileReadError(
                code="invalidRecord",
                detail=f"Vital File string record is not UTF-8: trackId={track_id}",
            ) from error
        sink.on_string_record(
            track_id=track_id,
            recorded_at=recorded_at,
            value=value,
        )


def _decode_device(payload: bytes) -> tuple[int, VitalDeviceDefinition]:
    cursor = _Cursor(payload, code="invalidDeviceMetadata")
    device_id = cursor.u32("device id")
    device_type = cursor.string("device type")
    name = cursor.string("device name")
    port = cursor.string("device port") if cursor.remaining else ""
    # Older VitalRecorder artifacts in the operational corpus append one
    # length-prefixed device-company field after the documented DEVINFO port.
    # The official vitaldb reader ignores this field. Decode exactly one such
    # legacy string so its length and UTF-8 are still validated; it is not part
    # of the current canonical device contract.
    if cursor.remaining:
        cursor.string("legacy device company")
    cursor.require_end("device metadata")
    return device_id, VitalDeviceDefinition(
        name=name or device_type,
        device_type=device_type,
        port=port,
    )


def _decode_track(
    payload: bytes,
    *,
    devices: dict[int, VitalDeviceDefinition],
) -> tuple[int, _TrackWireDefinition]:
    cursor = _Cursor(payload, code="invalidTrackMetadata")
    track_id = cursor.u16("track id")
    kind = VitalTrackKind.from_code(cursor.u8("track type"))
    format_code = cursor.u8("track format")
    value_struct = _FORMAT_STRUCTS.get(format_code)
    if (
        kind in (VitalTrackKind.WAVEFORM, VitalTrackKind.NUMERIC)
        and value_struct is None
    ):
        raise VitalFileReadError(
            code="invalidTrackMetadata",
            detail=(
                "Vital File numeric track format is unsupported: "
                f"trackId={track_id} format={format_code}"
            ),
        )
    name = cursor.string("track name")
    unit = cursor.optional_string("track unit", default="")
    minimum_display = cursor.optional_f32("track minimum display", default=0.0)
    maximum_display = cursor.optional_f32("track maximum display", default=0.0)
    color = cursor.optional_u32("track color", default=0)
    sample_rate = cursor.optional_f32("track sample rate", default=0.0)
    gain = cursor.optional_f64("track gain", default=0.0)
    offset = cursor.optional_f64("track offset", default=0.0)
    monitor_type_id = cursor.optional_u8("track monitor type", default=0)
    device_id = cursor.optional_u32("track device id", default=0)
    # Newer writers append record length and per-track times. They are wire
    # diagnostics, not canonical track state, but partial fields are invalid.
    cursor.optional_u32("track record length", default=0)
    cursor.optional_f64("track start time", default=0.0)
    cursor.optional_f64("track end time", default=0.0)
    cursor.require_end("track metadata")
    device_name = ""
    if device_id:
        device = devices.get(device_id)
        if device is None:
            raise VitalFileReadError(
                code="invalidTrackMetadata",
                detail=(
                    "Vital File track references an undefined device: "
                    f"trackId={track_id} deviceId={device_id}"
                ),
            )
        device_name = device.name
    dtname = f"{device_name}/{name}" if device_name else name
    definition = VitalTrackDefinition(
        dtname=dtname,
        name=name,
        device_name=device_name,
        kind=kind,
        format_code=format_code,
        unit=unit,
        sample_rate=sample_rate,
        minimum_display=minimum_display,
        maximum_display=maximum_display,
        color=color,
        gain=gain,
        offset=offset,
        monitor_type_id=monitor_type_id,
    )
    return track_id, _TrackWireDefinition(
        definition=definition,
        value_struct=value_struct,
    )


def _required_value_struct(track: _TrackWireDefinition) -> struct.Struct:
    if track.value_struct is None:
        raise VitalFileReadError(
            code="invalidTrackMetadata",
            detail=f"Vital File track has no numeric format: {track.definition.dtname}",
        )
    return track.value_struct


class _Cursor:
    def __init__(self, payload: bytes, *, code: str) -> None:
        self.payload = payload
        self.position = 0
        self.code = code

    @property
    def remaining(self) -> int:
        return len(self.payload) - self.position

    def u8(self, field: str) -> int:
        return int(self._unpack(struct.Struct("<B"), field))

    def u16(self, field: str) -> int:
        return int(self._unpack(struct.Struct("<H"), field))

    def u32(self, field: str) -> int:
        return int(self._unpack(struct.Struct("<I"), field))

    def f32(self, field: str) -> float:
        return float(self._unpack(struct.Struct("<f"), field))

    def f64(self, field: str) -> float:
        return float(self._unpack(struct.Struct("<d"), field))

    def string(self, field: str) -> str:
        length = self.u32(f"{field} length")
        encoded = self._take(length, field)
        try:
            return encoded.decode("utf-8")
        except UnicodeDecodeError as error:
            raise VitalFileReadError(
                code=self.code,
                detail=f"Vital File {field} is not UTF-8",
            ) from error

    def optional_string(self, field: str, *, default: str) -> str:
        return self.string(field) if self.remaining else default

    def optional_u8(self, field: str, *, default: int) -> int:
        return self.u8(field) if self.remaining else default

    def optional_u32(self, field: str, *, default: int) -> int:
        return self.u32(field) if self.remaining else default

    def optional_f32(self, field: str, *, default: float) -> float:
        return self.f32(field) if self.remaining else default

    def optional_f64(self, field: str, *, default: float) -> float:
        return self.f64(field) if self.remaining else default

    def require_end(self, field: str) -> None:
        if self.remaining:
            raise VitalFileReadError(
                code=self.code,
                detail=(
                    f"Vital File {field} has unexpected trailing bytes: "
                    f"{self.remaining}"
                ),
            )

    def _unpack(self, value_struct: struct.Struct, field: str) -> Any:
        return value_struct.unpack(self._take(value_struct.size, field))[0]

    def _take(self, size: int, field: str) -> bytes:
        end = self.position + size
        if end > len(self.payload):
            raise VitalFileReadError(
                code=self.code,
                detail=(
                    f"Vital File {field} is truncated: "
                    f"required={size} available={self.remaining}"
                ),
            )
        value = self.payload[self.position : end]
        self.position = end
        return value


def _read_up_to(stream: _ReadableStream, size: int) -> bytes:
    chunks: list[bytes] = []
    received = 0
    while received < size:
        chunk = stream.read(size - received)
        if not chunk:
            break
        chunks.append(chunk)
        received += len(chunk)
    return b"".join(chunks)


def _read_exact(stream: _ReadableStream, size: int, *, code: str) -> bytes:
    data = _read_up_to(stream, size)
    if len(data) != size:
        raise VitalFileReadError(
            code=code,
            detail=(
                f"Vital File stream is truncated: required={size} received={len(data)}"
            ),
        )
    return data


def _discard_exact(stream: _ReadableStream, size: int) -> None:
    remaining = size
    while remaining:
        chunk = stream.read(min(STREAM_CHUNK_BYTES, remaining))
        if not chunk:
            raise VitalFileReadError(
                code="truncatedPacket",
                detail=(
                    f"Vital File packet payload is truncated: remaining={remaining}"
                ),
            )
        remaining -= len(chunk)
