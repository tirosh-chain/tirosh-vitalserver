"""Use case result data contracts."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.testkit.domain.recorder.models import RecorderRoom
from tirosh_vitalserver.testkit.schemas.http import HttpResponse


@dataclass(frozen=True)
class UploadResult:
    path: Path
    bytes_sent: int
    response: HttpResponse
    error: str | None = None


@dataclass(frozen=True)
class RecorderSendResult:
    bytes_sent: int
    response: HttpResponse
    attempt: int
    error: str | None = None


@dataclass(frozen=True)
class RealtimeSendResult:
    bytes_sent: int
    attempt: int
    elapsed_seconds: float
    error: str | None = None


@dataclass(frozen=True)
class RealtimeStreamResult:
    messages_sent: int
    bytes_sent: int
    elapsed_seconds: float
    error: str | None = None


@dataclass(frozen=True)
class RecorderVisibilityResult:
    room: RecorderRoom
    response: HttpResponse


@dataclass(frozen=True)
class TransferSummary:
    results: tuple[UploadResult | RecorderSendResult | RealtimeSendResult, ...]
    elapsed_seconds: float


@dataclass(frozen=True)
class StreamSummary:
    results: tuple[RealtimeStreamResult, ...]
    elapsed_seconds: float
