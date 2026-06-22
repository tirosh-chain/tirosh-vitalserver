"""Outbound ports used by testkit use cases."""

from __future__ import annotations

from collections.abc import Callable, Mapping
from pathlib import Path
from typing import TYPE_CHECKING, Any, Protocol

from tirosh_vitalserver.testkit.schemas.http import HttpResponse
from tirosh_vitalserver.testkit.types.json import JsonValue

if TYPE_CHECKING:
    from tirosh_vitalserver.testkit.application.recorder_session.models import (
        VirtualRecorderSessionSnapshot,
        VirtualRecorderVitalArtifact,
        VirtualRecorderVitalUploadResult,
    )
    from tirosh_vitalserver.testkit.application.recorder_session.recording import (
        SessionVitalPlayback,
    )


class VitalServerPort(Protocol):
    """HTTP operations expected from a VitalServer adapter."""

    def health(self, path: str = "/check") -> HttpResponse: ...

    def device_metadata(self, bed_id: str) -> HttpResponse: ...

    def upload_vital_file(
        self,
        path: str | Path,
        *,
        vrcode: str | None = None,
        endpoint: str = "/upload",
        form_fields: Mapping[str, str] | None = None,
    ) -> HttpResponse: ...

    def send_recorder_payload(
        self,
        payload: Mapping[str, JsonValue],
        *,
        endpoint: str = "/api/send",
    ) -> HttpResponse: ...


class SocketIoClientPort(Protocol):
    """Socket.IO client operations used by realtime recorder adapters."""

    connected: bool

    def emit(self, event: str, data: Any = None) -> None: ...

    def on(self, event: str, handler: Callable[..., None]) -> None: ...

    def sleep(self, seconds: float) -> None: ...

    def disconnect(self) -> None: ...


class SocketIoConnectorPort(Protocol):
    """Factory for Socket.IO clients connected to one VitalServer instance."""

    def __call__(
        self,
        base_url: str,
        *,
        timeout: float = 30.0,
    ) -> SocketIoClientPort: ...


class SendDataEmitterPort(Protocol):
    """One-shot Socket.IO `send_data` emitter."""

    def __call__(
        self,
        base_url: str,
        encoded: bytes,
        *,
        timeout: float = 30.0,
    ) -> None: ...


class RecorderManagementPort(Protocol):
    """Management operations sent to VitalServer for simulated recorders."""

    def delete_vrecorder(
        self,
        base_url: str,
        vrcode: str,
        *,
        timeout: float = 5.0,
    ) -> None: ...

    def delete_bed(
        self,
        base_url: str,
        *,
        bed_id: str,
        bed_name: str,
        timeout: float = 5.0,
    ) -> None: ...


class SessionVitalFileExporterPort(Protocol):
    """Session artifact writer for VitalDB `.vital` files."""

    def export_session_vital_file(
        self,
        snapshot: VirtualRecorderSessionSnapshot,
        playback: SessionVitalPlayback,
    ) -> VirtualRecorderVitalArtifact: ...


class SessionVitalFileUploaderPort(Protocol):
    """Uploader for generated session `.vital` artifacts."""

    def upload_session_vital_file(
        self,
        *,
        target_url: str,
        artifact_path: str | Path,
        vrcode: str | None,
        endpoint: str,
    ) -> VirtualRecorderVitalUploadResult: ...
