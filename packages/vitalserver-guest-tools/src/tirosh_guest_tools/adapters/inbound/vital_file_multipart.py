"""Bounded-memory multipart staging for Guest Vital File uploads."""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from email import policy
from email.message import Message
from email.parser import BytesParser
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import BinaryIO, Protocol

from tirosh_guest_tools.application.guest_control.ports import VitalFileUploadSource

READ_CHUNK_BYTES = 64 * 1024
MAX_HEADER_LINE_BYTES = 8 * 1024
MAX_PART_HEADER_BYTES = 32 * 1024
MAX_UPLOAD_PARTS = 32


class VitalFileMultipartError(Exception):
    def __init__(self, *, code: str, detail: str) -> None:
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}")


class MultipartInputStream(Protocol):
    def read(self, size: int = -1) -> bytes:
        raise NotImplementedError

    def readline(self, size: int = -1) -> bytes:
        raise NotImplementedError


@dataclass(frozen=True)
class StagedVitalFileUploadSource:
    file_name: str
    path: Path
    size_bytes: int

    def open(self) -> BinaryIO:
        return self.path.open("rb")


@contextmanager
def staged_vital_file_uploads(
    stream: MultipartInputStream,
    *,
    content_length: int,
    content_type: str,
    staging_root: Path | None = None,
) -> Iterator[list[VitalFileUploadSource]]:
    """Stage multipart files to request-owned storage with bounded reads."""

    boundary = _multipart_boundary(content_type)
    if content_length <= 0:
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload requires a positive Content-Length.",
        )
    limited = _LimitedReader(stream, content_length)
    try:
        temporary_directory = TemporaryDirectory(
            prefix="vitalserver-upload-",
            dir=staging_root,
        )
    except OSError as error:
        raise VitalFileMultipartError(
            code="vitalFileUploadStagingFailed",
            detail=(
                f"Vital Files upload staging directory could not be created: {error}"
            ),
        ) from error

    with temporary_directory as temporary:
        directory = Path(temporary)
        try:
            sources: list[VitalFileUploadSource] = _stage_parts(
                limited,
                boundary=boundary,
                directory=directory,
            )
        except OSError as error:
            raise VitalFileMultipartError(
                code="vitalFileUploadStagingFailed",
                detail=f"Vital Files upload could not be staged: {error}",
            ) from error
        trailing = limited.read_remaining()
        if trailing not in (b"", b"\r\n"):
            raise VitalFileMultipartError(
                code="vitalFileUploadInvalid",
                detail="Vital Files upload has unexpected multipart epilogue bytes.",
            )
        if limited.remaining != 0:
            raise VitalFileMultipartError(
                code="truncatedUpload",
                detail=(
                    "Vital Files upload ended before Content-Length: "
                    f"remaining={limited.remaining}"
                ),
            )
        if not sources:
            raise VitalFileMultipartError(
                code="vitalFileUploadInvalid",
                detail="Select at least one .vital file.",
            )
        yield sources


class _LimitedReader:
    def __init__(self, stream: MultipartInputStream, content_length: int) -> None:
        self.stream = stream
        self.remaining = content_length

    def readline(self, limit: int) -> bytes:
        if self.remaining == 0:
            return b""
        data = self.stream.readline(min(limit, self.remaining))
        self.remaining -= len(data)
        return data

    def read(self, size: int) -> bytes:
        if self.remaining == 0:
            return b""
        data = self.stream.read(min(size, self.remaining))
        self.remaining -= len(data)
        return data

    def read_remaining(self) -> bytes:
        chunks: list[bytes] = []
        total_bytes = 0
        while self.remaining > 0:
            chunk = self.read(min(READ_CHUNK_BYTES, self.remaining))
            if not chunk:
                break
            chunks.append(chunk)
            total_bytes += len(chunk)
            if total_bytes > READ_CHUNK_BYTES:
                raise VitalFileMultipartError(
                    code="vitalFileUploadInvalid",
                    detail="Vital Files upload multipart epilogue is too large.",
                )
        return b"".join(chunks)


def _multipart_boundary(content_type: str) -> bytes:
    try:
        encoded_content_type = content_type.encode("latin-1")
    except UnicodeEncodeError as error:
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload Content-Type must use Latin-1 characters.",
        ) from error
    header = BytesParser(policy=policy.default).parsebytes(
        b"Content-Type: " + encoded_content_type + b"\r\n\r\n"
    )
    if header.get_content_type() != "multipart/form-data":
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload requires multipart/form-data.",
        )
    boundary = header.get_boundary()
    if not isinstance(boundary, str) or not boundary:
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload multipart boundary is missing.",
        )
    try:
        encoded = boundary.encode("ascii")
    except UnicodeEncodeError as error:
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload multipart boundary must be ASCII.",
        ) from error
    if len(encoded) > 200 or b"\r" in encoded or b"\n" in encoded:
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload multipart boundary is invalid.",
        )
    return encoded


def _stage_parts(
    reader: _LimitedReader,
    *,
    boundary: bytes,
    directory: Path,
) -> list[VitalFileUploadSource]:
    delimiter = b"--" + boundary
    if reader.readline(MAX_HEADER_LINE_BYTES) != delimiter + b"\r\n":
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload multipart opening boundary is invalid.",
        )

    sources: list[VitalFileUploadSource] = []
    while True:
        if len(sources) >= MAX_UPLOAD_PARTS:
            raise VitalFileMultipartError(
                code="vitalFileUploadInvalid",
                detail=(
                    "Vital Files upload contains too many files: "
                    f"maximum={MAX_UPLOAD_PARTS}"
                ),
            )
        headers = _part_headers(reader)
        filename = _part_filename(headers)
        path = directory / f"part-{len(sources):04d}.vital"
        with path.open("wb") as output:
            size_bytes, closed = _copy_part(
                reader,
                output,
                delimiter=delimiter,
            )
        sources.append(
            StagedVitalFileUploadSource(
                file_name=filename,
                path=path,
                size_bytes=size_bytes,
            )
        )
        if closed:
            return sources


def _part_headers(reader: _LimitedReader) -> Message:
    lines: list[bytes] = []
    size = 0
    while True:
        line = reader.readline(MAX_HEADER_LINE_BYTES)
        if not line:
            raise VitalFileMultipartError(
                code="truncatedUpload",
                detail="Vital Files upload ended inside multipart headers.",
            )
        if len(line) == MAX_HEADER_LINE_BYTES and not line.endswith(b"\n"):
            raise VitalFileMultipartError(
                code="vitalFileUploadInvalid",
                detail="Vital Files upload multipart header line is too large.",
            )
        size += len(line)
        if size > MAX_PART_HEADER_BYTES:
            raise VitalFileMultipartError(
                code="vitalFileUploadInvalid",
                detail="Vital Files upload multipart headers are too large.",
            )
        if line == b"\r\n":
            break
        lines.append(line)
    return BytesParser(policy=policy.default).parsebytes(b"".join(lines) + b"\r\n")


def _part_filename(headers: Message) -> str:
    if headers.get_content_disposition() != "form-data":
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload contains an invalid multipart part.",
        )
    if headers.get_param("name", header="content-disposition") != "files":
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Vital Files upload only accepts multipart field 'files'.",
        )
    filename = headers.get_filename()
    if not isinstance(filename, str) or not filename:
        raise VitalFileMultipartError(
            code="vitalFileUploadInvalid",
            detail="Every Vital Files upload part requires a filename.",
        )
    return filename


def _copy_part(
    reader: _LimitedReader,
    output: BinaryIO,
    *,
    delimiter: bytes,
) -> tuple[int, bool]:
    pending = b""
    size_bytes = 0
    while True:
        line = reader.readline(READ_CHUNK_BYTES)
        if not line:
            raise VitalFileMultipartError(
                code="truncatedUpload",
                detail="Vital Files upload ended before the closing boundary.",
            )
        if line in (delimiter + b"\r\n", delimiter + b"--\r\n"):
            if not pending.endswith(b"\r\n"):
                raise VitalFileMultipartError(
                    code="vitalFileUploadInvalid",
                    detail="Vital Files upload multipart content delimiter is invalid.",
                )
            content = pending[:-2]
            output.write(content)
            size_bytes += len(content)
            return size_bytes, line == delimiter + b"--\r\n"
        output.write(pending)
        size_bytes += len(pending)
        pending = line
