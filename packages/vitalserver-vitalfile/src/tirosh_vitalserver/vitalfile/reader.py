"""Version-dispatched VitalDB adapter normalized to canonical Core contracts."""

from __future__ import annotations

import gzip
import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from tirosh_vitalserver.core.domain.vital_file import (
    VITAL_HEADER_PREFIX_LENGTH,
    VitalDeviceDefinition,
    VitalFileFormatError,
    VitalFileFormatVersion,
    VitalFileHeader,
    VitalFileManifest,
    VitalTrackDefinition,
    VitalTrackKind,
    probe_vital_header,
)


class VitalFileReadError(Exception):
    """Report an explicit external reader failure without creating file state."""

    def __init__(self, *, code: str, detail: str) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}")


class _VitalDbFile(Protocol):
    dtstart: object
    dtend: object
    devs: object
    trks: object

    def get_track_samples(
        self,
        dtname: str,
        interval: float,
    ) -> Sequence[object]: ...


@dataclass(frozen=True, slots=True)
class VitalFileSource:
    """A canonical manifest plus explicitly requested sample reads."""

    manifest: VitalFileManifest
    _source: _VitalDbFile

    def track_samples(
        self,
        dtname: str,
        *,
        interval_seconds: float,
    ) -> Sequence[object]:
        """Read one canonical track at an explicit interval."""

        self.manifest.track(dtname)
        if not math.isfinite(interval_seconds) or interval_seconds <= 0:
            raise VitalFileReadError(
                code="invalidSampleInterval",
                detail=(
                    "Vital File sample interval must be finite and positive: "
                    f"{interval_seconds}"
                ),
            )
        try:
            return self._source.get_track_samples(dtname, interval_seconds)
        except Exception as error:
            raise VitalFileReadError(
                code="trackReadFailed",
                detail=f"Vital File track read failed: {dtname}: {error}",
            ) from error


@dataclass(frozen=True, slots=True)
class _VitalDbVersionReader:
    version: VitalFileFormatVersion

    def inspect(self, path: Path, header: VitalFileHeader) -> VitalFileManifest:
        self._validate_version(header)
        # v1/v2 base headers do not carry the complete time range. Their readers
        # must consume records to produce canonical times; v3 can remain header-only.
        header_only = self.version is VitalFileFormatVersion.V3
        source = _load_vitaldb_file(path, header_only=header_only)
        return _canonical_manifest(source, header=header)

    def open(self, path: Path, header: VitalFileHeader) -> VitalFileSource:
        self._validate_version(header)
        source = _load_vitaldb_file(path, header_only=False)
        return VitalFileSource(
            manifest=_canonical_manifest(source, header=header),
            _source=source,
        )

    def _validate_version(self, header: VitalFileHeader) -> None:
        if header.format_version is not self.version:
            raise VitalFileReadError(
                code="readerVersionMismatch",
                detail=(
                    f"{self.version.name} reader received "
                    f"{header.format_version.name} input"
                ),
            )


class VitalDbVitalFileReader:
    """Select the reader declared by the file instead of guessing its version."""

    def __init__(self) -> None:
        readers = (
            _VitalDbVersionReader(VitalFileFormatVersion.V1),
            _VitalDbVersionReader(VitalFileFormatVersion.V2),
            _VitalDbVersionReader(VitalFileFormatVersion.V3),
        )
        self._readers = {reader.version: reader for reader in readers}

    def open(self, path: Path) -> VitalFileSource:
        """Validate, dispatch, and normalize one gzip Vital File."""

        header = self._header(path)
        reader = self._readers[header.format_version]
        return reader.open(path, header)

    def inspect(self, path: Path) -> VitalFileManifest:
        """Return canonical metadata using each version's explicit read policy."""

        header = self._header(path)
        reader = self._readers[header.format_version]
        return reader.inspect(path, header)

    @staticmethod
    def _header(path: Path) -> VitalFileHeader:
        if path.suffix.lower() != ".vital" or not path.is_file():
            raise VitalFileReadError(
                code="sourceUnavailable",
                detail=f"Vital File source is unavailable: {path}",
            )
        return read_vital_file_header(path)


def read_vital_file_header(path: Path) -> VitalFileHeader:
    """Read only the bounded gzip prefix required by the declared header."""

    try:
        with gzip.open(path, "rb") as stream:
            prefix = stream.read(VITAL_HEADER_PREFIX_LENGTH)
            if len(prefix) < VITAL_HEADER_PREFIX_LENGTH:
                payload = prefix
            else:
                header_length = int.from_bytes(prefix[8:10], byteorder="little")
                payload = prefix + stream.read(header_length)
    except (EOFError, OSError) as error:
        raise VitalFileReadError(
            code="decodeFailed",
            detail=f"Vital File gzip decode failed: {path.name}: {error}",
        ) from error
    return probe_vital_header(payload)


def _load_vitaldb_file(path: Path, *, header_only: bool) -> _VitalDbFile:
    try:
        from vitaldb import VitalFile
    except ModuleNotFoundError as error:
        raise VitalFileReadError(
            code="readerUnavailable",
            detail="vitaldb package is required for Vital File reads",
        ) from error
    try:
        source: _VitalDbFile = VitalFile(str(path), header_only=header_only)
    except Exception as error:
        raise VitalFileReadError(
            code="decodeFailed",
            detail=f"Vital File decode failed: {path.name}: {error}",
        ) from error
    return source


def _canonical_manifest(
    source: _VitalDbFile,
    *,
    header: VitalFileHeader,
) -> VitalFileManifest:
    tracks_value = source.trks
    if not isinstance(tracks_value, Mapping):
        raise VitalFileReadError(
            code="invalidReaderContract",
            detail="vitaldb reader did not provide a track mapping",
        )
    devices_value = source.devs
    if not isinstance(devices_value, Mapping):
        raise VitalFileReadError(
            code="invalidReaderContract",
            detail="vitaldb reader did not provide a device mapping",
        )
    return VitalFileManifest(
        header=header,
        started_at=_finite_float(source.dtstart, field="dtstart"),
        ended_at=_finite_float(source.dtend, field="dtend"),
        devices=tuple(_canonical_device(device) for device in devices_value.values()),
        tracks=tuple(_canonical_track(track) for track in tracks_value.values()),
    )


def _canonical_device(source: object) -> VitalDeviceDefinition:
    return VitalDeviceDefinition(
        name=_required_string(source, "name", location="device"),
        device_type=_required_string(source, "type", location="device"),
        port=_required_string(source, "port", location="device", allow_empty=True),
    )


def _canonical_track(source: object) -> VitalTrackDefinition:
    dtname = _required_string(source, "dtname", location="track")
    return VitalTrackDefinition(
        dtname=dtname,
        name=_required_string(source, "name", location=dtname),
        device_name=_required_string(
            source,
            "dname",
            location=dtname,
            allow_empty=True,
        ),
        kind=VitalTrackKind.from_code(_required_int(source, "type", location=dtname)),
        format_code=_required_int(source, "fmt", location=dtname),
        unit=_required_string(source, "unit", location=dtname, allow_empty=True),
        sample_rate=_required_float(source, "srate", location=dtname),
        minimum_display=_required_float(source, "mindisp", location=dtname),
        maximum_display=_required_float(source, "maxdisp", location=dtname),
        color=_required_int(source, "col", location=dtname),
        gain=_required_float(source, "gain", location=dtname),
        offset=_required_float(source, "offset", location=dtname),
        monitor_type_id=_required_int(source, "montype", location=dtname),
    )


def _required_string(
    source: object,
    field: str,
    *,
    location: str,
    allow_empty: bool = False,
) -> str:
    value = getattr(source, field, None)
    if not isinstance(value, str) or (not allow_empty and not value):
        raise VitalFileFormatError(
            code=_metadata_error_code(location),
            detail=f"Vital {location} requires string {field}",
        )
    return value


def _required_int(source: object, field: str, *, location: str) -> int:
    value = getattr(source, field, None)
    if isinstance(value, bool) or not isinstance(value, int):
        raise VitalFileFormatError(
            code=_metadata_error_code(location),
            detail=f"Vital {location} requires integer {field}",
        )
    return value


def _required_float(source: object, field: str, *, location: str) -> float:
    value = getattr(source, field, None)
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise VitalFileFormatError(
            code=_metadata_error_code(location),
            detail=f"Vital {location} requires numeric {field}",
        )
    result = float(value)
    if not math.isfinite(result):
        raise VitalFileFormatError(
            code=_metadata_error_code(location),
            detail=f"Vital {location} requires finite {field}",
        )
    return result


def _metadata_error_code(location: str) -> str:
    return "invalidDeviceMetadata" if location == "device" else "invalidTrackMetadata"


def _finite_float(value: object, *, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise VitalFileFormatError(
            code="invalidFileMetadata",
            detail=f"Vital File requires numeric {field}",
        )
    result = float(value)
    if not math.isfinite(result):
        raise VitalFileFormatError(
            code="invalidFileMetadata",
            detail=f"Vital File requires finite {field}",
        )
    return result
