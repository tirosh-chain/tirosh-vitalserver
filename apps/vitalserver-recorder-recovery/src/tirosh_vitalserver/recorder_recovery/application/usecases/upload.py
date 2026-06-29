"""Use case for uploading `.vital` files to VitalServer."""

from __future__ import annotations

import time
from collections.abc import Iterable
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Protocol

from tirosh_vitalserver.core.domain.vital_file.models import PayloadFile
from tirosh_vitalserver.recorder_recovery.application.results import (
    TransferSummary,
    UploadResult,
)
from tirosh_vitalserver.recorder_recovery.schemas.http import HttpResponse


class VitalServerUploadPort(Protocol):
    def upload_vital_file(
        self,
        path: str | Path,
        *,
        vrcode: str | None = None,
        endpoint: str = "/upload",
        form_fields: dict[str, str] | None = None,
    ) -> HttpResponse:
        """Upload one `.vital` file and return the HTTP response."""


def upload_vital_files(
    client: VitalServerUploadPort,
    payloads: Iterable[PayloadFile],
    *,
    vrcode: str | None = None,
    concurrency: int = 1,
    repeat: int = 1,
    endpoint: str = "/upload",
) -> TransferSummary:
    """Upload `.vital` payloads repeatedly and collect transfer metrics."""

    payload_list = tuple(payloads)
    if not payload_list:
        raise ValueError("at least one payload is required")
    if concurrency < 1:
        raise ValueError("concurrency must be greater than 0")
    if repeat < 1:
        raise ValueError("repeat must be greater than 0")

    started = time.perf_counter()

    results: list[UploadResult] = []
    jobs = [(payload, attempt) for attempt in range(repeat) for payload in payload_list]

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [
            executor.submit(_upload_one, client, payload, vrcode, endpoint, attempt)
            for payload, attempt in jobs
        ]

        for future in as_completed(futures):
            results.append(future.result())

    elapsed = time.perf_counter() - started

    return TransferSummary(results=tuple(results), elapsed_seconds=elapsed)


def _upload_one(
    client: VitalServerUploadPort,
    payload: PayloadFile,
    vrcode: str | None,
    endpoint: str,
    attempt: int,
) -> UploadResult:
    try:
        response = client.upload_vital_file(
            payload.path,
            vrcode=vrcode,
            endpoint=endpoint,
            form_fields={"attempt": str(attempt)},
        )

        return UploadResult(
            path=payload.path, bytes_sent=payload.size_bytes, response=response
        )
    except Exception as exc:
        response = HttpResponse(
            status_code=0, headers={}, body=b"", elapsed_seconds=0.0
        )

        return UploadResult(
            path=payload.path,
            bytes_sent=payload.size_bytes,
            response=response,
            error=str(exc),
        )
