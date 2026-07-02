from __future__ import annotations

import http.client
import json
import mimetypes
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from urllib.parse import urljoin, urlparse
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4

from .model import (
    LabBed,
    LabRecorder,
    LabRecorderExecutionResult,
    LabSession,
    utc_now_iso,
)


@dataclass(frozen=True)
class LabRecorderSendReceipt:
    status_code: int
    bytes_sent: int


@dataclass(frozen=True)
class LabVitalFileUploadReceipt:
    filename: str
    endpoint: str
    target_url: str
    status_code: int
    bytes_sent: int
    response_text: str
    ok: bool

    def as_json(self) -> dict[str, object]:
        return {
            "filename": self.filename,
            "endpoint": self.endpoint,
            "targetURL": self.target_url,
            "statusCode": self.status_code,
            "bytesSent": self.bytes_sent,
            "responseText": self.response_text,
            "ok": self.ok,
        }


class LabRecorderPayloadSender(Protocol):
    def send(
        self,
        *,
        target_url: str,
        payload: dict[str, object],
    ) -> LabRecorderSendReceipt:
        """Send one Vital Recorder payload to a VitalServer-compatible endpoint."""


class LabVitalFileUploader(Protocol):
    def upload(
        self,
        *,
        target_url: str,
        file_path: Path,
        endpoint: str,
        vrcode: str | None = None,
    ) -> LabVitalFileUploadReceipt:
        """Upload one mounted .vital file to a VitalServer upload endpoint."""


class VitalServerRecorderPayloadSender:
    def __init__(self, *, endpoint: str = "/api/send", timeout_seconds: float = 10.0):
        self.endpoint = endpoint
        self.timeout_seconds = timeout_seconds

    def send(
        self,
        *,
        target_url: str,
        payload: dict[str, object],
    ) -> LabRecorderSendReceipt:
        body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode()
        request = Request(
            urljoin(target_url.rstrip("/") + "/", self.endpoint.lstrip("/")),
            data=body,
            headers={
                "Content-Type": "application/json",
                "Content-Length": str(len(body)),
            },
            method="POST",
        )
        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                status_code = int(response.status)
        except HTTPError as error:
            raise LabRecorderSendError(
                f"VitalServer recorder payload send failed: status={error.code}"
            ) from error
        except URLError as error:
            raise LabRecorderSendError(
                f"VitalServer recorder payload send failed: {error.reason}"
            ) from error

        if status_code < 200 or status_code >= 300:
            raise LabRecorderSendError(
                f"VitalServer recorder payload send failed: status={status_code}"
            )

        return LabRecorderSendReceipt(status_code=status_code, bytes_sent=len(body))


class LabRecorderSendError(Exception):
    pass


class VitalServerVitalFileUploader:
    def __init__(self, *, timeout_seconds: float = 60.0) -> None:
        self.timeout_seconds = timeout_seconds

    def upload(
        self,
        *,
        target_url: str,
        file_path: Path,
        endpoint: str,
        vrcode: str | None = None,
    ) -> LabVitalFileUploadReceipt:
        boundary = f"----tirosh-vitalserver-lab-{uuid4().hex}"
        form_fields = {"vrcode": vrcode} if vrcode is not None else {}
        header, footer = _multipart_file_boundaries(
            boundary=boundary,
            file_field="vitalfile",
            file_path=file_path,
            form_fields=form_fields,
        )
        content_length = len(header) + file_path.stat().st_size + len(footer)
        headers = {
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(content_length),
        }

        response = _stream_file_request(
            base_url=target_url,
            endpoint=endpoint,
            headers=headers,
            header=header,
            file_path=file_path,
            footer=footer,
            timeout_seconds=self.timeout_seconds,
        )
        response_text = response.body.decode("utf-8", errors="replace")
        ok = 200 <= response.status_code < 300 and "success" in response_text.lower()
        return LabVitalFileUploadReceipt(
            filename=file_path.name,
            endpoint=endpoint,
            target_url=target_url,
            status_code=response.status_code,
            bytes_sent=content_length,
            response_text=response_text,
            ok=ok,
        )


@dataclass(frozen=True)
class _UploadHTTPResponse:
    status_code: int
    body: bytes


class LabVitalFileUploadError(Exception):
    pass


class LabExecutionEngine:
    def __init__(
        self,
        *,
        sender: LabRecorderPayloadSender,
        vital_file_uploader: LabVitalFileUploader | None = None,
    ) -> None:
        self.sender = sender
        self.vital_file_uploader = vital_file_uploader or VitalServerVitalFileUploader()

    def start_session(
        self,
        *,
        session: LabSession,
        beds: tuple[LabBed, ...],
        recorders: tuple[LabRecorder, ...],
    ) -> tuple[LabRecorderExecutionResult, ...]:
        beds_by_id = {bed.bed_id: bed for bed in beds}
        if session.target_url is None:
            return tuple(
                LabRecorderExecutionResult(
                    recorder_id=recorder.recorder_id,
                    messages_sent=0,
                    last_send_state="skipped",
                    last_send_at=None,
                    last_send_error="targetURL is not configured",
                )
                for recorder in recorders
            )

        results: list[LabRecorderExecutionResult] = []
        for recorder in recorders:
            bed = beds_by_id.get(recorder.bed_id)
            if bed is None:
                results.append(
                    LabRecorderExecutionResult(
                        recorder_id=recorder.recorder_id,
                        messages_sent=0,
                        last_send_state="failed",
                        last_send_at=utc_now_iso(),
                        last_send_error=(
                            "Lab recorder bed read model is missing: "
                            f"{recorder.bed_id}"
                        ),
                    )
                )
                continue
            try:
                payload = lab_recorder_payload(
                    session=session,
                    bed=bed,
                    recorder=recorder,
                )
            except LabRecorderSendError as error:
                results.append(
                    LabRecorderExecutionResult(
                        recorder_id=recorder.recorder_id,
                        messages_sent=0,
                        last_send_state="failed",
                        last_send_at=utc_now_iso(),
                        last_send_error=str(error),
                    )
                )
                continue
            try:
                self.sender.send(target_url=session.target_url, payload=payload)
            except LabRecorderSendError as error:
                results.append(
                    LabRecorderExecutionResult(
                        recorder_id=recorder.recorder_id,
                        messages_sent=0,
                        last_send_state="failed",
                        last_send_at=utc_now_iso(),
                        last_send_error=str(error),
                    )
                )
                continue
            results.append(
                LabRecorderExecutionResult(
                    recorder_id=recorder.recorder_id,
                    messages_sent=1,
                    last_send_state="sent",
                    last_send_at=utc_now_iso(),
                    last_send_error=None,
                )
            )
        return tuple(results)

    def upload_vital_file(
        self,
        *,
        target_url: str,
        file_path: Path,
        endpoint: str = "/upload",
        vrcode: str | None = None,
    ) -> LabVitalFileUploadReceipt:
        try:
            return self.vital_file_uploader.upload(
                target_url=target_url,
                file_path=file_path,
                endpoint=endpoint,
                vrcode=vrcode,
            )
        except (OSError, LabVitalFileUploadError) as error:
            raise LabRecorderSendError(str(error)) from error


def _stream_file_request(
    *,
    base_url: str,
    endpoint: str,
    headers: dict[str, str],
    header: bytes,
    file_path: Path,
    footer: bytes,
    timeout_seconds: float,
    chunk_size: int = 1024 * 1024,
) -> _UploadHTTPResponse:
    parsed_base = urlparse(base_url)
    request_url = urlparse(urljoin(base_url.rstrip("/") + "/", endpoint.lstrip("/")))
    host = request_url.hostname or parsed_base.hostname
    if host is None:
        raise LabVitalFileUploadError(f"targetURL host is missing: {base_url}")
    port = request_url.port
    if request_url.scheme == "https":
        connection: http.client.HTTPConnection = http.client.HTTPSConnection(
            host,
            port,
            timeout=timeout_seconds,
        )
    elif request_url.scheme == "http":
        connection = http.client.HTTPConnection(host, port, timeout=timeout_seconds)
    else:
        raise LabVitalFileUploadError(
            f"targetURL scheme is unsupported: {request_url.scheme}"
        )

    request_path = request_url.path or "/"
    if request_url.query:
        request_path = f"{request_path}?{request_url.query}"

    try:
        connection.putrequest("POST", request_path)
        for key, value in headers.items():
            connection.putheader(key, value)
        connection.endheaders()
        connection.send(header)
        with file_path.open("rb") as file_obj:
            while chunk := file_obj.read(chunk_size):
                connection.send(chunk)
        connection.send(footer)
        response = connection.getresponse()
        return _UploadHTTPResponse(
            status_code=int(response.status),
            body=response.read(),
        )
    finally:
        connection.close()


def _multipart_file_boundaries(
    *,
    boundary: str,
    file_field: str,
    file_path: Path,
    form_fields: dict[str, str],
) -> tuple[bytes, bytes]:
    chunks: list[bytes] = []
    for name, value in form_fields.items():
        chunks.append(f"--{boundary}\r\n".encode("ascii"))
        chunks.append((f'Content-Disposition: form-data; name="{name}"\r\n\r\n').encode())
        chunks.append(str(value).encode("utf-8"))
        chunks.append(b"\r\n")

    content_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    chunks.append(f"--{boundary}\r\n".encode("ascii"))
    chunks.append(
        (
            f'Content-Disposition: form-data; name="{file_field}"; '
            f'filename="{file_path.name}"\r\n'
        ).encode()
    )
    chunks.append(f"Content-Type: {content_type}\r\n\r\n".encode("ascii"))
    footer = f"\r\n--{boundary}--\r\n".encode("ascii")
    return b"".join(chunks), footer


def lab_recorder_payload(
    *,
    session: LabSession,
    bed: LabBed,
    recorder: LabRecorder,
) -> dict[str, object]:
    if session.scenario_id == "vital-file-replay":
        if session.vital_file_path is None:
            raise LabRecorderSendError("vital file replay source is not configured")
        return lab_vital_file_replay_payload(
            session=session,
            bed=bed,
            recorder=recorder,
        )

    now = time.time()
    room = {
        "roomname": bed.name,
        "seqid": 1,
        "dtstart": now,
        "dtend": now + 1,
        "dtcase": now,
        "dtapp": now,
        "dtserver": now,
        "ptcon": 1,
        "recording": 1,
        "devs": [
            {
                "type": "simulator",
                "name": "VitalServer Lab",
                "status": "connected",
            }
        ],
        "trks": [
            {
                "name": "HR",
                "type": "num",
                "unit": "/min",
                "recs": [{"dt": 0, "val": 75}],
            },
            {
                "name": "SPO2",
                "type": "num",
                "unit": "%",
                "recs": [{"dt": 0, "val": 98}],
            },
            {
                "name": "ECG_II",
                "type": "wav",
                "srate": 125,
                "mindisp": -1,
                "maxdisp": 1,
                "recs": [{"dt": 0, "val": [0.0, 0.2, 0.9, 0.2, 0.0]}],
            },
        ],
        "evts": [
            {
                "dt": 0,
                "val": f"Lab session started: {session.name}",
            }
        ],
        "filts": [],
    }
    return {
        "vrcode": recorder.vrcode,
        "ver": "vitalserver-lab",
        "rooms": {bed.name: room},
    }


def lab_vital_file_replay_payload(
    *,
    session: LabSession,
    bed: LabBed,
    recorder: LabRecorder,
) -> dict[str, object]:
    now = time.time()
    room = {
        "roomname": bed.name,
        "seqid": 1,
        "dtstart": now,
        "dtend": now + 1,
        "dtcase": now,
        "dtapp": now,
        "dtserver": now,
        "ptcon": 1,
        "recording": 1,
        "devs": [
            {
                "type": "replay",
                "name": "VitalServer Lab",
                "status": "connected",
            }
        ],
        "trks": [
            {
                "name": "HR",
                "type": "num",
                "unit": "/min",
                "recs": [{"dt": 0, "val": 75}],
            },
            {
                "name": "SPO2",
                "type": "num",
                "unit": "%",
                "recs": [{"dt": 0, "val": 98}],
            },
        ],
        "evts": [
            {
                "dt": 0,
                "val": "Lab vital file replay started",
            }
        ],
        "filts": [],
    }
    return {
        "vrcode": recorder.vrcode,
        "ver": "vitalserver-lab",
        "source": {"kind": "vital-file-replay"},
        "rooms": {bed.name: room},
    }
