from __future__ import annotations

import http.client
import json
import math
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

    def close_recorder(self, *, target_url: str, vrcode: str) -> None:
        """Close the connection explicitly owned by one recorder."""

    def close_all(self) -> None:
        """Close every recorder connection owned by this sender."""


class SocketIOClient(Protocol):
    connected: bool

    def connect(self, url: str, *, transports: list[str]) -> None: ...

    def emit(self, event: str, data: object) -> None: ...

    def sleep(self, seconds: float) -> None: ...

    def disconnect(self) -> None: ...


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


@dataclass
class _RunningLabSession:
    stop_event: threading.Event
    thread: threading.Thread
    active_recorder_ids: set[str]
    active_recorder_ids_lock: threading.Lock
    target_url: str
    recorder_vrcodes: dict[str, str]


class VitalServerRecorderPayloadSender:
    def __init__(
        self,
        *,
        timeout_seconds: float = 10.0,
        settle_seconds: float = 0.25,
    ):
        self.timeout_seconds = timeout_seconds
        self.settle_seconds = settle_seconds
        self._clients: dict[tuple[str, str], SocketIOClient] = {}
        self._clients_lock = threading.Lock()

    def send(
        self,
        *,
        target_url: str,
        payload: dict[str, object],
    ) -> LabRecorderSendReceipt:
        body = _encode_socketio_send_data_payload(payload)
        vrcode = _payload_vrcode(payload)
        if vrcode is None:
            raise LabRecorderSendError(
                "VitalServer recorder Socket.IO payload is missing vrcode"
            )
        try:
            client = self._connected_client(target_url=target_url, vrcode=vrcode)
        except Exception as error:
            if isinstance(error, LabRecorderSendError):
                raise
            raise LabRecorderSendError(
                f"VitalServer recorder Socket.IO connection failed: {error}"
            ) from error

        try:
            client.emit("send_data", body)
        except Exception as error:
            self._discard_client(target_url=target_url, vrcode=vrcode, client=client)
            raise LabRecorderSendError(
                f"VitalServer recorder Socket.IO send_data failed: {error}"
            ) from error

        return LabRecorderSendReceipt(transport="socket.io", bytes_sent=len(body))

    def close_recorder(self, *, target_url: str, vrcode: str) -> None:
        with self._clients_lock:
            client = self._clients.pop((target_url, vrcode), None)
        if client is not None:
            self._disconnect_client(client)

    def close_all(self) -> None:
        with self._clients_lock:
            clients = tuple(self._clients.values())
            self._clients.clear()
        for client in clients:
            self._disconnect_client(client)

    def _connected_client(
        self,
        *,
        target_url: str,
        vrcode: str,
    ) -> SocketIOClient:
        key = (target_url, vrcode)
        with self._clients_lock:
            client = self._clients.get(key)
            if client is not None and getattr(client, "connected", False):
                return client
            if client is not None:
                self._clients.pop(key, None)
                self._disconnect_client(client)
            client = _connect_socketio(
                target_url,
                timeout_seconds=self.timeout_seconds,
            )
            try:
                client.emit("join_vr", vrcode)
            except Exception:
                self._disconnect_client(client)
                raise
            self._clients[key] = client
            return client

    def _discard_client(
        self,
        *,
        target_url: str,
        vrcode: str,
        client: SocketIOClient,
    ) -> None:
        with self._clients_lock:
            if self._clients.get((target_url, vrcode)) is client:
                self._clients.pop((target_url, vrcode), None)
        self._disconnect_client(client)

    def _disconnect_client(self, client: SocketIOClient) -> None:
        if not getattr(client, "connected", False):
            return
        if self.settle_seconds > 0:
            client.sleep(self.settle_seconds)
        client.disconnect()


class LabRecorderSendError(Exception):
    pass


def _connect_socketio(
    target_url: str,
    *,
    timeout_seconds: float,
) -> SocketIOClient:
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
                active_recorder_ids={recorder.recorder_id for recorder in recorders},
                initial_sequence=2,
                result_sink=result_sink,
            )
        return results

    def start_recorder(
        self,
        *,
        session: LabSession,
        beds: tuple[LabBed, ...],
        recorders: tuple[LabRecorder, ...],
        recorder_id: str,
        result_sink: LabRecorderExecutionResultSink | None = None,
    ) -> LabRecorderExecutionResult | None:
        recorder = next(
            (
                candidate
                for candidate in recorders
                if candidate.recorder_id == recorder_id
            ),
            None,
        )
        if recorder is None:
            return None
        if session.target_url is None:
            result = LabRecorderExecutionResult(
                recorder_id=recorder.recorder_id,
                messages_sent=0,
                last_send_state="skipped",
                last_send_at=None,
                last_send_error="targetURL is not configured",
            )
            if result_sink is not None:
                result_sink((result,))
            return result
        beds_by_id = {bed.bed_id: bed for bed in beds}
        with self._running_sessions_lock:
            running = self._running_sessions.get(session.session_id)
        if running is not None:
            with running.active_recorder_ids_lock:
                running.active_recorder_ids.add(recorder_id)
        results = self._send_session_frame(
            session=session,
            beds_by_id=beds_by_id,
            recorders=(recorder,),
            sequence=1,
        )
        if running is None:
            self._start_session_runner(
                session=session,
                beds_by_id=beds_by_id,
                recorders=recorders,
                active_recorder_ids={recorder_id},
                initial_sequence=2,
                result_sink=result_sink,
            )
        if result_sink is not None:
            result_sink(results)
        return results[0]

    def stop_recorder(self, session_id: str, recorder_id: str) -> None:
        with self._running_sessions_lock:
            running = self._running_sessions.get(session_id)
        if running is None:
            return
        with running.active_recorder_ids_lock:
            running.active_recorder_ids.discard(recorder_id)
        vrcode = running.recorder_vrcodes.get(recorder_id)
        if vrcode is not None:
            self.sender.close_recorder(
                target_url=running.target_url,
                vrcode=vrcode,
            )

    def stop_session(self, session_id: str) -> None:
        with self._running_sessions_lock:
            running = self._running_sessions.pop(session_id, None)
        if running is None:
            return
        running.stop_event.set()
        if threading.current_thread() is not running.thread:
            running.thread.join(timeout=2)
        for vrcode in running.recorder_vrcodes.values():
            self.sender.close_recorder(
                target_url=running.target_url,
                vrcode=vrcode,
            )

    def shutdown(self) -> None:
        with self._running_sessions_lock:
            session_ids = tuple(self._running_sessions)
        for session_id in session_ids:
            self.stop_session(session_id)
        self.sender.close_all()

    def _start_session_runner(
        self,
        *,
        session: LabSession,
        beds_by_id: dict[str, LabBed],
        recorders: tuple[LabRecorder, ...],
        active_recorder_ids: set[str],
        initial_sequence: int,
        result_sink: LabRecorderExecutionResultSink | None,
    ) -> None:
        target_url = session.target_url
        if target_url is None:
            raise LabRecorderSendError("targetURL is not configured")
        stop_event = threading.Event()
        active_recorder_ids_lock = threading.Lock()

        def run() -> None:
            sequence = initial_sequence
            while not stop_event.wait(self.frame_interval_seconds):
                with active_recorder_ids_lock:
                    active_recorders = tuple(
                        recorder
                        for recorder in recorders
                        if recorder.recorder_id in active_recorder_ids
                    )
                if not active_recorders:
                    continue
                results = self._send_session_frame(
                    session=session,
                    beds_by_id=beds_by_id,
                    recorders=active_recorders,
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
                active_recorder_ids=active_recorder_ids,
                active_recorder_ids_lock=active_recorder_ids_lock,
                target_url=target_url,
                recorder_vrcodes={
                    recorder.recorder_id: recorder.vrcode for recorder in recorders
                },
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
        target_url = session.target_url
        if target_url is None:
            raise LabRecorderSendError("targetURL is not configured")
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
                            f"Lab recorder bed read model is missing: {recorder.bed_id}"
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
                self.sender.send(target_url=target_url, payload=payload)
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
        chunks.append(
            (f'Content-Disposition: form-data; name="{name}"\r\n\r\n').encode()
        )
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
    waveforms = lab_waveform_frame(
        scenario_id=session.scenario_id,
        profile=profile,
        started_at=now,
    )
    room = {
        "roomname": bed.name,
        "seqid": sequence,
        "dtstart": now,
        "dtend": now + 1,
        "dtcase": now,
        "dtapp": now,
        "dtserver": now + 1,
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
                "recs": [{"dt": now, "val": waveforms["ecg"]}],
            },
            {
                "id": 1002,
                "name": "PLETH",
                "dname": "VitalServer Lab",
                "montype": "PLETH_WAV",
                "type": "wav",
                "srate": 100,
                "unit": "%",
                "mindisp": 0,
                "maxdisp": 100,
                "recs": [{"dt": now, "val": waveforms["pleth"]}],
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
                "recs": [{"dt": now, "val": waveforms["co2"]}],
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


def lab_waveform_frame(
    *,
    scenario_id: str,
    profile: dict[str, object],
    started_at: float,
    frame_seconds: float = 1.0,
) -> dict[str, list[float]]:
    heart_rate = _profile_number(profile, "hr")
    respiratory_rate = _profile_number(profile, "rr")
    sample_rates = {"ecg": 125, "pleth": 100, "co2": 25}
    values: dict[str, list[float]] = {}
    for waveform, sample_rate in sample_rates.items():
        sample_count = round(sample_rate * frame_seconds)
        values[waveform] = [
            _lab_waveform_sample(
                waveform=waveform,
                sample_time=started_at + index / sample_rate,
                heart_rate=heart_rate,
                respiratory_rate=respiratory_rate,
                arrhythmia=scenario_id == "arrhythmia-like-variation",
            )
            for index in range(sample_count)
        ]
    return values


def _lab_waveform_sample(
    *,
    waveform: str,
    sample_time: float,
    heart_rate: float,
    respiratory_rate: float,
    arrhythmia: bool,
) -> float:
    if waveform == "co2":
        phase = _cycle_phase(sample_time, respiratory_rate)
        if phase < 0.35:
            value = 0.0
        elif phase < 0.48:
            value = (phase - 0.35) / 0.13 * 38
        elif phase < 0.82:
            value = 38 + math.sin((phase - 0.48) / 0.34 * math.pi) * 2
        else:
            value = max(0.0, 38 * (1 - (phase - 0.82) / 0.18))
        return round(value, 3)

    phase = _cycle_phase(sample_time, heart_rate)
    if arrhythmia:
        phase = (
            phase
            + math.sin(sample_time * 0.9) * 0.12
            + math.sin(sample_time * 2.7) * 0.04
        ) % 1
    if waveform == "ecg":
        value = (
            _gaussian(phase, center=0.18, width=0.025, amplitude=0.06)
            - _gaussian(phase, center=0.36, width=0.012, amplitude=0.18)
            + _gaussian(phase, center=0.39, width=0.008, amplitude=1.0)
            - _gaussian(phase, center=0.42, width=0.014, amplitude=0.28)
            + _gaussian(phase, center=0.65, width=0.055, amplitude=0.22)
        )
        return round(value - 0.02, 4)

    if waveform == "pleth":
        if phase < 0.18:
            value = 38 + phase / 0.18 * 26
        elif phase < 0.42:
            value = 64 - (phase - 0.18) / 0.24 * 9
        else:
            value = 55 - (phase - 0.42) / 0.58 * 17
        value -= _gaussian(phase, center=0.32, width=0.018, amplitude=3.0)
        return round(value, 3)

    raise LabRecorderSendError(f"unsupported Lab waveform: {waveform}")


def _cycle_phase(sample_time: float, cycles_per_minute: float) -> float:
    if cycles_per_minute <= 0:
        raise LabRecorderSendError("Lab waveform rate must be greater than zero")
    return (sample_time * cycles_per_minute / 60) % 1


def _gaussian(
    phase: float,
    *,
    center: float,
    width: float,
    amplitude: float,
) -> float:
    distance = min(abs(phase - center), 1 - abs(phase - center))
    return amplitude * math.exp(-0.5 * (distance / width) ** 2)


def _profile_number(profile: dict[str, object], key: str) -> float:
    value = profile.get(key)
    if not isinstance(value, int | float):
        raise LabRecorderSendError(f"Lab signal profile is missing numeric {key}")
    return float(value)


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
