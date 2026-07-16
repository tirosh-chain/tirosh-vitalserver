from __future__ import annotations

import gzip
import json
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import UTC, datetime
from io import BytesIO
from pathlib import Path
from time import monotonic, sleep
from typing import Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin
from urllib.request import Request, urlopen
from uuid import uuid4

from tirosh_guest_tools.domain.errors import GuestContractError
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    VitalFileUploadFailure,
    VitalFileUploadItem,
    VitalFileUploadResult,
)
from tirosh_guest_tools.domain.runtime_config import RuntimeConfig


@dataclass(frozen=True)
class VitalServerHTTPResponse:
    status_code: int
    headers: Mapping[str, str]
    body: bytes


class VitalServerHTTPTransport(Protocol):
    def request(
        self,
        *,
        method: str,
        url: str,
        headers: Mapping[str, str],
        body: bytes | None,
        timeout: float,
    ) -> VitalServerHTTPResponse:
        raise NotImplementedError


class URLlibVitalServerHTTPTransport:
    def request(
        self,
        *,
        method: str,
        url: str,
        headers: Mapping[str, str],
        body: bytes | None,
        timeout: float,
    ) -> VitalServerHTTPResponse:
        request = Request(url, data=body, headers=dict(headers), method=method)
        try:
            with urlopen(request, timeout=timeout) as response:
                return VitalServerHTTPResponse(
                    status_code=response.status,
                    headers=dict(response.headers.items()),
                    body=response.read(),
                )
        except HTTPError as error:
            return VitalServerHTTPResponse(
                status_code=error.code,
                headers=dict(error.headers.items()),
                body=error.read(),
            )


class VitalServerVitalFileLibrary:
    """Uses VitalServer's upload and indexed file-list APIs as the owner boundary."""

    def __init__(
        self,
        *,
        base_url: str,
        guest_mount: Path,
        runtime_config: Callable[[], RuntimeConfig],
        transport: VitalServerHTTPTransport | None = None,
        timeout_seconds: float = 300.0,
        index_wait_seconds: float = 300.0,
        index_poll_interval_seconds: float = 1.0,
        monotonic_clock: Callable[[], float] = monotonic,
        sleep_fn: Callable[[float], None] = sleep,
    ) -> None:
        if index_wait_seconds < 0:
            raise ValueError("index_wait_seconds must not be negative")
        if index_poll_interval_seconds <= 0:
            raise ValueError("index_poll_interval_seconds must be positive")
        self._base_url = base_url.rstrip("/") + "/"
        self._guest_mount = guest_mount
        self._runtime_config = runtime_config
        self._transport = transport or URLlibVitalServerHTTPTransport()
        self._timeout_seconds = timeout_seconds
        self._index_wait_seconds = index_wait_seconds
        self._index_poll_interval_seconds = index_poll_interval_seconds
        self._monotonic_clock = monotonic_clock
        self._sleep = sleep_fn

    def list_files(self) -> list[dict[str, object]]:
        token = self._login_access_token()
        query = urlencode({"access_token": token, "unixtimestamp": "1"})
        response = self._request(
            method="GET",
            path=f"/api/filelist?{query}",
        )
        # VitalServer's file-list endpoint uses this exact 404 document to
        # declare an authenticated, but empty, indexed library. It is not a
        # missing route. Other 404 responses remain dependency failures.
        if self._is_empty_file_list_response(response):
            return []
        if response.status_code != 200:
            raise GuestControlDependencyError(
                f"VitalServer file list failed with HTTP {response.status_code}.",
                kind="vitalFileLibraryReadFailed",
            )
        try:
            decoded = gzip.decompress(response.body)
            document = json.loads(decoded.decode("utf-8"))
        except (gzip.BadGzipFile, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise GuestControlDependencyError(
                f"VitalServer file list response is invalid: {error}",
                kind="vitalFileLibraryInvalidResponse",
            ) from error
        if not isinstance(document, list):
            raise GuestControlDependencyError(
                "VitalServer file list response must be an array.",
                kind="vitalFileLibraryInvalidResponse",
            )

        files: list[dict[str, object]] = []
        names: set[str] = set()
        for item in document:
            if not isinstance(item, dict):
                raise self._invalid_file_list("file item must be an object")
            filename = item.get("filename")
            size = item.get("filesize")
            if not isinstance(filename, str) or not self._valid_filename(filename):
                raise self._invalid_file_list("filename is invalid")
            if filename in names:
                raise self._invalid_file_list(f"duplicate filename: {filename}")
            names.add(filename)
            if not isinstance(size, (int, float)) or isinstance(size, bool) or size < 0:
                raise self._invalid_file_list(f"filesize is invalid: {filename}")
            relative_path = self._storage_relative_path(filename)
            files.append(
                {
                    "displayName": filename,
                    "relativePath": relative_path,
                    "guestPath": str(self._guest_mount / relative_path),
                    "sizeBytes": int(size),
                    "modifiedAt": self._modified_at(item.get("dtupload")),
                }
            )
        return sorted(files, key=lambda item: str(item["relativePath"]).lower())

    def import_files(self, files: list[tuple[str, bytes]]) -> VitalFileUploadResult:
        candidates, failures = self._upload_candidates(files)
        if not candidates:
            return VitalFileUploadResult.from_items([], failures)

        indexed_before = {str(item["displayName"]): item for item in self.list_files()}
        upload_candidates: list[tuple[str, bytes]] = []
        for filename, content in candidates:
            if filename in indexed_before:
                failures.append(
                    VitalFileUploadFailure(
                        file_name=filename,
                        reason="VitalServer already indexes this filename.",
                    )
                )
                continue
            upload_candidates.append((filename, content))

        accepted: list[tuple[str, bytes]] = []
        for filename, content in upload_candidates:
            response = self._upload(filename, content)
            response_text = response.body.decode("utf-8", errors="replace").strip()
            upload_succeeded = (
                response.status_code in range(200, 300) and response_text == "success"
            )
            if not upload_succeeded:
                failures.append(
                    VitalFileUploadFailure(
                        file_name=filename,
                        reason=(
                            "VitalServer upload failed: "
                            f"HTTP {response.status_code} body={response_text!r}"
                        ),
                    )
                )
                continue
            accepted.append((filename, content))

        if not accepted:
            return VitalFileUploadResult.from_items([], failures)

        try:
            indexed_after, _ = self._wait_for_index(
                [filename for filename, _ in accepted]
            )
        except GuestControlDependencyError as error:
            failures.extend(
                VitalFileUploadFailure(
                    file_name=filename,
                    reason=(
                        "VitalServer accepted the upload, but index verification "
                        f"failed: {error.message}"
                    ),
                )
                for filename, _ in accepted
            )
            return VitalFileUploadResult.from_items([], failures)

        uploaded: list[VitalFileUploadItem] = []
        for filename, content in accepted:
            indexed = indexed_after.get(filename)
            if indexed is None:
                failures.append(
                    VitalFileUploadFailure(
                        file_name=filename,
                        reason=(
                            "VitalServer accepted the upload but did not report "
                            "the file in its index within "
                            f"{self._index_wait_seconds:g}s."
                        ),
                    )
                )
                continue
            uploaded.append(
                VitalFileUploadItem(
                    file_name=filename,
                    relative_path=str(indexed["relativePath"]),
                    size_bytes=len(content),
                )
            )
        return VitalFileUploadResult.from_items(uploaded, failures)

    def _wait_for_index(
        self, uploaded_filenames: list[str]
    ) -> tuple[dict[str, dict[str, object]], tuple[str, ...]]:
        deadline = self._monotonic_clock() + self._index_wait_seconds
        while True:
            indexed = {str(item["displayName"]): item for item in self.list_files()}
            missing = tuple(
                filename for filename in uploaded_filenames if filename not in indexed
            )
            if not missing:
                return indexed, missing
            if self._monotonic_clock() >= deadline:
                return indexed, missing
            self._sleep(
                min(
                    self._index_poll_interval_seconds,
                    deadline - self._monotonic_clock(),
                )
            )

    def _login_access_token(self) -> str:
        try:
            config = self._runtime_config()
        except (OSError, json.JSONDecodeError, GuestContractError) as error:
            raise GuestControlDependencyError(
                f"VitalServer credentials are unavailable: {error}",
                kind="vitalFileLibraryAuthenticationUnavailable",
            ) from error
        body = urlencode({"id": "admin", "pw": config.admin_password}).encode()
        response = self._request(
            method="POST",
            path="/api/login",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            body=body,
        )
        if response.status_code != 200:
            raise GuestControlDependencyError(
                f"VitalServer login failed with HTTP {response.status_code}.",
                kind="vitalFileLibraryAuthenticationFailed",
            )
        try:
            document = json.loads(response.body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise GuestControlDependencyError(
                f"VitalServer login response is invalid: {error}",
                kind="vitalFileLibraryInvalidResponse",
            ) from error
        token = document.get("access_token") if isinstance(document, dict) else None
        login_succeeded = isinstance(document, dict) and document.get("res") is True
        if not login_succeeded or not isinstance(token, str) or not token:
            raise GuestControlDependencyError(
                "VitalServer login did not return an access token.",
                kind="vitalFileLibraryAuthenticationFailed",
            )
        return token

    def _upload(self, filename: str, content: bytes) -> VitalServerHTTPResponse:
        boundary = f"----tirosh-vitalserver-{uuid4().hex}"
        prefix = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="vitalfile"; '
            f'filename="{filename}"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n"
        ).encode()
        body = prefix + content + f"\r\n--{boundary}--\r\n".encode()
        return self._request(
            method="POST",
            path="/upload",
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            body=body,
        )

    @staticmethod
    def _is_empty_file_list_response(response: VitalServerHTTPResponse) -> bool:
        if response.status_code != 404:
            return False
        try:
            document = json.loads(response.body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return False
        return document == {"message": "No result found"}

    def _request(
        self,
        *,
        method: str,
        path: str,
        headers: Mapping[str, str] | None = None,
        body: bytes | None = None,
    ) -> VitalServerHTTPResponse:
        url = urljoin(self._base_url, path.lstrip("/"))
        try:
            return self._transport.request(
                method=method,
                url=url,
                headers=headers or {},
                body=body,
                timeout=self._timeout_seconds,
            )
        except (OSError, URLError) as error:
            raise GuestControlDependencyError(
                f"VitalServer request failed url={url}: {error}",
                kind="vitalFileLibraryUnavailable",
            ) from error

    def _upload_candidates(
        self, files: list[tuple[str, bytes]]
    ) -> tuple[list[tuple[str, bytes]], list[VitalFileUploadFailure]]:
        if not files:
            raise GuestControlDependencyError(
                "Select at least one .vital file.",
                kind="vitalFileUploadInvalid",
            )
        names: set[str] = set()
        candidates: list[tuple[str, bytes]] = []
        failures: list[VitalFileUploadFailure] = []
        for filename, content in files:
            try:
                self._validate_upload_candidate(filename, content, names)
            except GuestControlDependencyError as error:
                failures.append(
                    VitalFileUploadFailure(file_name=filename, reason=error.message)
                )
                continue
            names.add(filename)
            candidates.append((filename, content))
        return candidates, failures

    def _validate_upload_candidate(
        self,
        filename: str,
        content: bytes,
        names: set[str],
    ) -> None:
        if not self._valid_filename(filename):
            raise GuestControlDependencyError(
                "Only .vital files can be uploaded: "
                f"{filename or '<missing filename>'}",
                kind="vitalFileUploadInvalid",
            )
        try:
            self._storage_relative_path(filename)
        except GuestControlDependencyError as error:
            raise GuestControlDependencyError(
                "VitalServer upload filename must follow "
                f"<bed>_YYMMDD_HHMMSS.vital: {filename}",
                kind="vitalFileUploadInvalid",
            ) from error
        if filename in names:
            raise GuestControlDependencyError(
                f"Upload contains duplicate filenames: {filename}",
                kind="vitalFileUploadInvalid",
            )
        self._validate_vital_file_content(filename, content)

    @staticmethod
    def _validate_vital_file_content(filename: str, content: bytes) -> None:
        try:
            with gzip.GzipFile(fileobj=BytesIO(content), mode="rb") as archive:
                if archive.read(4) != b"VITA":
                    raise GuestControlDependencyError(
                        f"Vital file is missing its VITA header: {filename}",
                        kind="vitalFileUploadInvalid",
                    )
                while archive.read(1024 * 1024):
                    pass
        except (gzip.BadGzipFile, EOFError, OSError) as error:
            raise GuestControlDependencyError(
                f"Vital file gzip stream is invalid: {filename}: {error}",
                kind="vitalFileUploadInvalid",
            ) from error

    @staticmethod
    def _valid_filename(filename: object) -> bool:
        return (
            isinstance(filename, str)
            and bool(filename)
            and Path(filename).name == filename
            and "\\" not in filename
            and '"' not in filename
            and "\r" not in filename
            and "\n" not in filename
            and Path(filename).suffix.lower() == ".vital"
        )

    @staticmethod
    def _storage_relative_path(filename: str) -> str:
        if len(filename) < 20:
            raise VitalServerVitalFileLibrary._invalid_file_list(
                f"filename cannot be mapped to VitalServer storage: {filename}"
            )
        bed_name = filename[:-20]
        yymmdd = filename[-19:-13]
        if not bed_name or len(yymmdd) != 6 or not yymmdd.isdigit():
            raise VitalServerVitalFileLibrary._invalid_file_list(
                f"filename cannot be mapped to VitalServer storage: {filename}"
            )
        yyyy_mm = f"{datetime.now(UTC).year // 100:02d}{yymmdd[:4]}"
        return (Path(bed_name) / yyyy_mm / yymmdd / filename).as_posix()

    @staticmethod
    def _modified_at(value: object) -> str | None:
        if value is None:
            return None
        if isinstance(value, str):
            try:
                numeric_value = float(value)
            except ValueError:
                return value
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            numeric_value = value
        else:
            raise VitalServerVitalFileLibrary._invalid_file_list("dtupload is invalid")
        return (
            datetime.fromtimestamp(numeric_value, UTC)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z")
        )

    @staticmethod
    def _invalid_file_list(detail: str) -> GuestControlDependencyError:
        return GuestControlDependencyError(
            f"VitalServer file list response is invalid: {detail}",
            kind="vitalFileLibraryInvalidResponse",
        )
