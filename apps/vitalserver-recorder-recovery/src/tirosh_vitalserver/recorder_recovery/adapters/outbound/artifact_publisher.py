"""Publish recovery artifacts through the VitalServer-owned library APIs."""

from __future__ import annotations

import gzip
import hashlib
import json
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path
from time import monotonic, sleep

from tirosh_vitalserver.recorder_recovery.application.ports import (
    ArtifactPublishDependencyError,
    IndexedVitalArtifact,
)
from tirosh_vitalserver.recorder_recovery.domain import RecoveryArtifactReceipt

from .vitalserver import VitalServerClient


class VitalServerArtifactPublisher:
    def __init__(
        self,
        *,
        base_url: str,
        admin_password: str,
        timeout_seconds: float = 300.0,
        index_wait_seconds: float = 300.0,
        index_poll_interval_seconds: float = 1.0,
        monotonic_clock: Callable[[], float] = monotonic,
        sleep_fn: Callable[[float], None] = sleep,
    ) -> None:
        if not base_url:
            raise ValueError("VitalServer publish base URL is required")
        if not admin_password:
            raise ValueError("VitalServer publish admin password is required")
        if index_wait_seconds < 0:
            raise ValueError("index_wait_seconds must not be negative")
        if index_poll_interval_seconds <= 0:
            raise ValueError("index_poll_interval_seconds must be positive")
        self._client = VitalServerClient(base_url, timeout=timeout_seconds)
        self._admin_password = admin_password
        self._index_wait_seconds = index_wait_seconds
        self._index_poll_interval_seconds = index_poll_interval_seconds
        self._monotonic = monotonic_clock
        self._sleep = sleep_fn

    def find_indexed(self, filename: str) -> IndexedVitalArtifact | None:
        return next(
            (item for item in self._list_indexed() if item.filename == filename),
            None,
        )

    def upload(self, receipt: RecoveryArtifactReceipt) -> None:
        path = _validated_artifact_path(receipt)
        try:
            response = self._client.upload_vital_file(path)
        except OSError as error:
            raise ArtifactPublishDependencyError(
                stage="upload",
                code="vitalServerUnavailable",
                message=f"VitalServer upload request failed: {error}",
            ) from error
        if not response.ok or response.text.strip() != "success":
            raise ArtifactPublishDependencyError(
                stage="upload",
                code="uploadRejected",
                message=(
                    "VitalServer upload was rejected: "
                    f"status={response.status_code} body={response.text.strip()!r}"
                ),
            )

    def wait_until_indexed(
        self,
        filename: str,
        *,
        size_bytes: int,
    ) -> IndexedVitalArtifact | None:
        deadline = self._monotonic() + self._index_wait_seconds
        while True:
            indexed = self.find_indexed(filename)
            if indexed is not None:
                if indexed.size_bytes != size_bytes:
                    raise ArtifactPublishDependencyError(
                        stage="indexVerification",
                        code="indexedSizeMismatch",
                        message=(
                            "VitalServer indexed artifact size differs from receipt: "
                            f"filename={filename} expected={size_bytes} "
                            f"actual={indexed.size_bytes}"
                        ),
                    )
                return indexed
            now = self._monotonic()
            if now >= deadline:
                return None
            self._sleep(min(self._index_poll_interval_seconds, deadline - now))

    def _list_indexed(self) -> tuple[IndexedVitalArtifact, ...]:
        token = self._login()
        try:
            response = self._client.filelist(token, unixtimestamp=1)
        except OSError as error:
            raise ArtifactPublishDependencyError(
                stage="libraryRead",
                code="vitalServerUnavailable",
                message=f"VitalServer file list request failed: {error}",
            ) from error
        if response.status_code == 404 and _is_empty_filelist(response.body):
            return ()
        if response.status_code != 200:
            raise ArtifactPublishDependencyError(
                stage="libraryRead",
                code="fileListRejected",
                message=f"VitalServer file list failed: status={response.status_code}",
            )
        try:
            document = json.loads(gzip.decompress(response.body).decode("utf-8"))
        except (gzip.BadGzipFile, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ArtifactPublishDependencyError(
                stage="libraryRead",
                code="fileListInvalid",
                message=f"VitalServer file list response is invalid: {error}",
            ) from error
        if not isinstance(document, list):
            raise ArtifactPublishDependencyError(
                stage="libraryRead",
                code="fileListInvalid",
                message="VitalServer file list response must be an array",
            )
        items: list[IndexedVitalArtifact] = []
        names: set[str] = set()
        for value in document:
            if not isinstance(value, dict):
                raise _invalid_filelist("file item must be an object")
            filename = value.get("filename")
            size = value.get("filesize")
            if not isinstance(filename, str) or not filename:
                raise _invalid_filelist("filename is invalid")
            if filename in names:
                raise _invalid_filelist(f"duplicate filename: {filename}")
            if (
                not isinstance(size, (int, float))
                or isinstance(size, bool)
                or size < 0
            ):
                raise _invalid_filelist(f"filesize is invalid: {filename}")
            names.add(filename)
            items.append(
                IndexedVitalArtifact(
                    filename=filename,
                    relative_path=_storage_relative_path(filename),
                    size_bytes=int(size),
                )
            )
        return tuple(items)

    def _login(self) -> str:
        try:
            response = self._client.login("admin", self._admin_password)
        except OSError as error:
            raise ArtifactPublishDependencyError(
                stage="authentication",
                code="vitalServerUnavailable",
                message=f"VitalServer login request failed: {error}",
            ) from error
        if response.status_code != 200:
            raise ArtifactPublishDependencyError(
                stage="authentication",
                code="authenticationFailed",
                message=f"VitalServer login failed: status={response.status_code}",
            )
        try:
            document = json.loads(response.body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ArtifactPublishDependencyError(
                stage="authentication",
                code="loginResponseInvalid",
                message=f"VitalServer login response is invalid: {error}",
            ) from error
        token = document.get("access_token") if isinstance(document, dict) else None
        if (
            not isinstance(document, dict)
            or document.get("res") is not True
            or not isinstance(token, str)
            or not token
        ):
            raise ArtifactPublishDependencyError(
                stage="authentication",
                code="authenticationFailed",
                message="VitalServer login did not return an access token",
            )
        return token


def _validated_artifact_path(receipt: RecoveryArtifactReceipt) -> Path:
    path = Path(receipt.path)
    try:
        stat = path.stat()
    except OSError as error:
        raise ArtifactPublishDependencyError(
            stage="artifactValidation",
            code="artifactUnavailable",
            message=f"recovery artifact cannot be read: path={path} error={error}",
        ) from error
    if not path.is_file() or path.name != receipt.filename:
        raise ArtifactPublishDependencyError(
            stage="artifactValidation",
            code="artifactIdentityMismatch",
            message=f"recovery artifact path does not match receipt: path={path}",
        )
    if stat.st_size != receipt.size_bytes:
        raise ArtifactPublishDependencyError(
            stage="artifactValidation",
            code="artifactSizeMismatch",
            message=(
                "recovery artifact size differs from receipt: "
                f"expected={receipt.size_bytes} actual={stat.st_size}"
            ),
        )
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
    except OSError as error:
        raise ArtifactPublishDependencyError(
            stage="artifactValidation",
            code="artifactUnavailable",
            message=f"recovery artifact cannot be read: path={path} error={error}",
        ) from error
    if digest.hexdigest() != receipt.sha256:
        raise ArtifactPublishDependencyError(
            stage="artifactValidation",
            code="artifactHashMismatch",
            message="recovery artifact SHA-256 differs from receipt",
        )
    return path


def _is_empty_filelist(body: bytes) -> bool:
    try:
        return json.loads(body.decode("utf-8")) == {"message": "No result found"}
    except (UnicodeDecodeError, json.JSONDecodeError):
        return False


def _storage_relative_path(filename: str) -> str:
    if Path(filename).name != filename or len(filename) < 20:
        raise _invalid_filelist(f"filename cannot be mapped: {filename}")
    bed_name = filename[:-20]
    yymmdd = filename[-19:-13]
    if not bed_name or len(yymmdd) != 6 or not yymmdd.isdigit():
        raise _invalid_filelist(f"filename cannot be mapped: {filename}")
    yyyy_mm = f"{datetime.now(UTC).year // 100:02d}{yymmdd[:4]}"
    return (Path(bed_name) / yyyy_mm / yymmdd / filename).as_posix()


def _invalid_filelist(message: str) -> ArtifactPublishDependencyError:
    return ArtifactPublishDependencyError(
        stage="libraryRead",
        code="fileListInvalid",
        message=f"VitalServer file list response is invalid: {message}",
    )
