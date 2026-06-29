"""Recorder recovery use case result contracts."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.recorder_recovery.schemas.http import HttpResponse


@dataclass(frozen=True)
class UploadResult:
    path: Path
    bytes_sent: int
    response: HttpResponse
    error: str | None = None


@dataclass(frozen=True)
class TransferSummary:
    results: tuple[UploadResult, ...]
    elapsed_seconds: float
