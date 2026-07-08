from __future__ import annotations

import http.client
import json
import mimetypes
import threading
import time
import zlib
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from urllib.parse import urljoin, urlparse
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
    transport: str
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


LabRecorderExecutionResultSink = Callable[
    [tuple[LabRecorderExecutionResult, ...]],
    None,
]


@dataclass(frozen=True)
class _RunningLabSession:
    stop_event: threading.Event
    thread: threading.Thread


class VitalServerRecorderPayloadSender:
    def __init__(
        self,
        *,
        timeout_seconds: float = 10.0,
        settle_seconds: float = 0.25,
    ):
        self.timeout_seconds = timeout_seconds
        self.settle_seconds = settle_seconds

    def send(
        self,
        *,
        target_url: str,
        payload: dict[str, object],
    ) -> LabRecorderSendReceipt:
        body = _encode_socketio_send_data_payload(payload)
        vrcode = _payload_vrcode(payload)
        try:
            client = _connect_socketio(target_url, timeout_seconds=self.timeout_seconds)
        except Exception as error:
            raise LabRecorderSendError(
                f"VitalServer recorder Socket.IO connection failed: {error}"
            ) from error

        try:
            if vrcode is not None:
                client.emit("join_vr", vrcode)
            client.emit("send_data", body)
            client.sleep(self.settle_seconds)
        except Exception as error:
            raise LabRecorderSendError(
                f"VitalServer recorder Socket.IO send_data failed: {error}"
            ) from error
        finally:
            if getattr(client, "connected", False):
                client.disconnect()

        return LabRecorderSendReceipt(transport="socket.io", bytes_sent=len(body))


class LabRecorderSendError(Exception):
    pass


def _connect_socketio(target_url: str, *, timeout_seconds: float):
    try:
        import socketio
    except ImportError as error:
        raise LabRecorderSendError(
            "python-socketio is required for VitalServer recorder Socket.IO send_data"
        ) from error

    client = socketio.Client(
        reconnection=False,
        request_timeout=timeout_seconds,
        logger=False,
        engineio_logger=False,
    )
    client.connect(target_url, transports=["websocket", "polling"])
    return client


def _encode_socketio_send_data_payload(payload: dict[str, object]) -> bytes:
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode(
        "utf-8"
    )
    return zlib.compress(body)


def _payload_vrcode(payload: dict[str, object]) -> str | None:
    value = payload.get("vrcode")
    return value if isinstance(value, str) and value else None


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
        frame_interval_seconds: float = 1.0,
    ) -> None:
        self.sender = sender
        self.vital_file_uploader = vital_file_uploader or VitalServerVitalFileUploader()
        self.frame_interval_seconds = max(0.0, frame_interval_seconds)
        self._running_sessions: dict[str, _RunningLabSession] = {}
        self._running_sessions_lock = threading.Lock()

    def start_session(
        self,
        *,
        session: LabSession,
        beds: tuple[LabBed, ...],
        recorders: tuple[LabRecorder, ...],
        result_sink: LabRecorderExecutionResultSink | None = None,
    ) -> tuple[LabRecorderExecutionResult, ...]:
        self.stop_session(session.session_id)
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

        results = self._send_session_frame(
            session=session,
            beds_by_id=beds_by_id,
            recorders=recorders,
            sequence=1,
        )
        if recorders:
            self._start_session_runner(
                session=session,
                beds_by_id=beds_by_id,
                recorders=recorders,
                initial_sequence=2,
                result_sink=result_sink,
            )
        return results

    def stop_session(self, session_id: str) -> None:
        with self._running_sessions_lock:
            running = self._running_sessions.pop(session_id, None)
        if running is None:
            return
        running.stop_event.set()
        if threading.current_thread() is not running.thread:
            running.thread.join(timeout=2)

    def shutdown(self) -> None:
        with self._running_sessions_lock:
            session_ids = tuple(self._running_sessions)
        for session_id in session_ids:
            self.stop_session(session_id)

    def _start_session_runner(
        self,
        *,
        session: LabSession,
        beds_by_id: dict[str, LabBed],
        recorders: tuple[LabRecorder, ...],
        initial_sequence: int,
        result_sink: LabRecorderExecutionResultSink | None,
    ) -> None:
        stop_event = threading.Event()

        def run() -> None:
            sequence = initial_sequence
            while not stop_event.wait(self.frame_interval_seconds):
                results = self._send_session_frame(
                    session=session,
                    beds_by_id=beds_by_id,
                    recorders=recorders,
                    sequence=sequence,
                )
                if result_sink is not None:
                    try:
                        result_sink(results)
                    except Exception as error:
                        print(
                            "[vitalserver-lab] recorder execution result save failed:",
                            str(error),
                        )
                sequence += 1

        thread = threading.Thread(
            target=run,
            name=f"lab-session-runner-{session.session_id}",
            daemon=True,
        )
        with self._running_sessions_lock:
            previous = self._running_sessions.pop(session.session_id, None)
            self._running_sessions[session.session_id] = _RunningLabSession(
                stop_event=stop_event,
                thread=thread,
            )
        if previous is not None:
            previous.stop_event.set()
        thread.start()

    def _send_session_frame(
        self,
        *,
        session: LabSession,
        beds_by_id: dict[str, LabBed],
        recorders: tuple[LabRecorder, ...],
        sequence: int,
    ) -> tuple[LabRecorderExecutionResult, ...]:
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
                    sequence=sequence,
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
    sequence: int = 1,
) -> dict[str, object]:
    if session.scenario_id == "vital-file-replay":
        if session.vital_file_path is None:
            raise LabRecorderSendError("vital file replay source is not configured")
        return lab_vital_file_replay_payload(
            session=session,
            bed=bed,
            recorder=recorder,
            sequence=sequence,
        )

    now = time.time()
    profile = lab_signal_profile(session.scenario_id)
    room = {
        "roomname": bed.name,
        "seqid": sequence,
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
                "id": 2001,
                "name": "HR",
                "dname": "VitalServer Lab",
                "montype": "ECG_HR",
                "type": "num",
                "unit": "/min",
                "recs": [{"dt": now, "val": profile["hr"]}],
            },
            {
                "id": 2002,
                "name": "PLETH_SPO2",
                "dname": "VitalServer Lab",
                "montype": "PLETH_SPO2",
                "type": "num",
                "unit": "%",
                "recs": [{"dt": now, "val": profile["spo2"]}],
            },
            {
                "id": 2003,
                "name": "ART_SBP",
                "dname": "VitalServer Lab",
                "montype": "IABP_SBP",
                "type": "num",
                "unit": "mmHg",
                "recs": [{"dt": now, "val": profile["abp_sys"]}],
            },
            {
                "id": 2004,
                "name": "ART_DBP",
                "dname": "VitalServer Lab",
                "montype": "IABP_DBP",
                "type": "num",
                "unit": "mmHg",
                "recs": [{"dt": now, "val": profile["abp_dia"]}],
            },
            {
                "id": 2005,
                "name": "ART_MBP",
                "dname": "VitalServer Lab",
                "montype": "IABP_MBP",
                "type": "num",
                "unit": "mmHg",
                "recs": [{"dt": now, "val": profile["abp_mbp"]}],
            },
            {
                "id": 2006,
                "name": "RR",
                "dname": "VitalServer Lab",
                "montype": "CO2_RR",
                "type": "num",
                "unit": "/min",
                "recs": [{"dt": now, "val": profile["rr"]}],
            },
            {
                "id": 2007,
                "name": "BT",
                "dname": "VitalServer Lab",
                "montype": "BT",
                "type": "num",
                "unit": "degC",
                "recs": [{"dt": now, "val": profile["bt"]}],
            },
            {
                "id": 1001,
                "name": "ECG",
                "dname": "VitalServer Lab",
                "montype": "ECG_WAV",
                "type": "wav",
                "srate": 125,
                "unit": "mV",
                "mindisp": -1,
                "maxdisp": 1,
                "recs": [{"dt": now, "val": profile["ecg"]}],
            },
            {
                "id": 1002,
                "name": "PLETH",
                "dname": "VitalServer Lab",
                "montype": "PLETH_WAV",
                "type": "wav",
                "srate": 62.5,
                "unit": "%",
                "mindisp": 0,
                "maxdisp": 1,
                "recs": [{"dt": now, "val": profile["pleth"]}],
            },
            {
                "id": 1003,
                "name": "CO2",
                "dname": "VitalServer Lab",
                "montype": "CO2_WAV",
                "type": "wav",
                "srate": 25,
                "unit": "mmHg",
                "mindisp": 0,
                "maxdisp": 50,
                "recs": [{"dt": now, "val": profile["co2"]}],
            },
        ],
        "evts": [
            {
                "dt": now,
                "val": f"{profile['event']}: {session.name}",
            }
        ],
        "filts": [],
    }
    return {
        "vrcode": recorder.vrcode,
        "ver": "vitalserver-lab",
        "rooms": {bed.name: room},
    }


def lab_signal_profile(scenario_id: str) -> dict[str, object]:
    profiles: dict[str, dict[str, object]] = {
        "baseline-monitoring": {
            "hr": 75,
            "spo2": 98,
            "abp_sys": 118,
            "abp_dia": 72,
            "abp_mbp": 88,
            "rr": 14,
            "bt": 36.8,
            "ecg": [0.0, 0.2, 0.9, 0.2, 0.0],
            "pleth": [5, 22, 78, 42, 12],
            "co2": [0, 2, 8, 28, 38, 35, 12],
            "event": "Baseline monitoring started",
        },
        "postoperative-recovery": {
            "hr": 88,
            "spo2": 97,
            "abp_sys": 112,
            "abp_dia": 68,
            "abp_mbp": 83,
            "rr": 16,
            "bt": 37.2,
            "ecg": [0.0, 0.18, 0.82, 0.24, 0.02],
            "pleth": [8, 24, 72, 48, 16],
            "co2": [0, 3, 10, 30, 39, 34, 14],
            "event": "Postoperative recovery profile started",
        },
        "hypotension-episode": {
            "hr": 116,
            "spo2": 96,
            "abp_sys": 82,
            "abp_dia": 46,
            "abp_mbp": 58,
            "rr": 20,
            "bt": 36.6,
            "ecg": [0.0, 0.22, 1.0, 0.25, 0.0],
            "pleth": [3, 14, 42, 24, 8],
            "co2": [0, 2, 9, 26, 36, 32, 10],
            "event": "Hypotension episode profile started",
        },
        "hypertension-episode": {
            "hr": 92,
            "spo2": 98,
            "abp_sys": 178,
            "abp_dia": 104,
            "abp_mbp": 129,
            "rr": 15,
            "bt": 36.9,
            "ecg": [0.0, 0.2, 0.88, 0.18, 0.0],
            "pleth": [6, 22, 68, 38, 10],
            "co2": [0, 2, 8, 27, 37, 33, 12],
            "event": "Hypertension episode profile started",
        },
        "tachycardia-response": {
            "hr": 138,
            "spo2": 97,
            "abp_sys": 126,
            "abp_dia": 76,
            "abp_mbp": 93,
            "rr": 22,
            "bt": 37.0,
            "ecg": [0.0, 0.16, 0.95, 0.16, 0.0],
            "pleth": [4, 20, 70, 32, 8],
            "co2": [0, 4, 14, 32, 38, 31, 9],
            "event": "Tachycardia response profile started",
        },
        "bradycardia-response": {
            "hr": 44,
            "spo2": 98,
            "abp_sys": 104,
            "abp_dia": 60,
            "abp_mbp": 75,
            "rr": 12,
            "bt": 36.7,
            "ecg": [0.0, 0.12, 0.74, 0.3, 0.04],
            "pleth": [8, 26, 82, 55, 18],
            "co2": [0, 2, 7, 24, 36, 34, 15],
            "event": "Bradycardia response profile started",
        },
        "desaturation-event": {
            "hr": 104,
            "spo2": 88,
            "abp_sys": 118,
            "abp_dia": 70,
            "abp_mbp": 86,
            "rr": 28,
            "bt": 36.9,
            "ecg": [0.0, 0.2, 0.86, 0.22, 0.0],
            "pleth": [2, 12, 52, 30, 8],
            "co2": [0, 3, 15, 35, 42, 30, 8],
            "event": "Desaturation event profile started",
        },
        "respiratory-variation": {
            "hr": 82,
            "spo2": 96,
            "abp_sys": 116,
            "abp_dia": 70,
            "abp_mbp": 85,
            "rr": 24,
            "bt": 36.8,
            "ecg": [0.0, 0.18, 0.84, 0.2, 0.0],
            "pleth": [4, 18, 72, 40, 12],
            "co2": [0, 4, 16, 34, 43, 28, 7],
            "event": "Respiratory variation profile started",
        },
        "fever-trend": {
            "hr": 108,
            "spo2": 97,
            "abp_sys": 122,
            "abp_dia": 74,
            "abp_mbp": 90,
            "rr": 20,
            "bt": 38.7,
            "ecg": [0.0, 0.2, 0.9, 0.22, 0.0],
            "pleth": [5, 20, 74, 42, 14],
            "co2": [0, 3, 11, 29, 39, 34, 12],
            "event": "Fever trend profile started",
        },
        "arrhythmia-like-variation": {
            "hr": 96,
            "spo2": 97,
            "abp_sys": 120,
            "abp_dia": 72,
            "abp_mbp": 88,
            "rr": 16,
            "bt": 36.8,
            "ecg": [0.0, 0.24, 0.7, 0.18, 0.0, 0.05, 1.05, 0.12],
            "pleth": [5, 18, 70, 30, 6, 16, 62, 26],
            "co2": [0, 2, 8, 28, 38, 32, 10],
            "event": "Arrhythmia-like variation profile started",
        },
    }
    return profiles.get(scenario_id, profiles["baseline-monitoring"])


def lab_vital_file_replay_payload(
    *,
    session: LabSession,
    bed: LabBed,
    recorder: LabRecorder,
    sequence: int = 1,
) -> dict[str, object]:
    now = time.time()
    room = {
        "roomname": bed.name,
        "seqid": sequence,
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
                "id": 2001,
                "name": "HR",
                "dname": "VitalServer Lab",
                "montype": "ECG_HR",
                "type": "num",
                "unit": "/min",
                "recs": [{"dt": now, "val": 75}],
            },
            {
                "id": 2002,
                "name": "PLETH_SPO2",
                "dname": "VitalServer Lab",
                "montype": "PLETH_SPO2",
                "type": "num",
                "unit": "%",
                "recs": [{"dt": now, "val": 98}],
            },
        ],
        "evts": [
            {
                "dt": now,
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
