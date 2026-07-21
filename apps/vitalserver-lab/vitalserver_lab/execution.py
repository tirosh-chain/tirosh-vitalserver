from __future__ import annotations

import json
import math
import threading
import time
import zlib
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from .archive_finalization import (
    LabArchiveFinalizationError,
    LabArchiveFinalizationProgress,
    LabArchiveFinalizationReason,
    LabArchiveFinalizationReceipt,
    LabRecorderArchiveFinalizer,
)
from .model import (
    LabBed,
    LabRecorder,
    LabRecorderExecutionResult,
    LabSession,
    utc_now_iso,
)
from .vital_replay import (
    LabReplayGapPolicy,
    LabReplayStringTrackPolicy,
    LabVitalReplaySource,
    LabVitalReplaySourceFactory,
    VitalReplaySourceError,
)
from .vital_replay_spool import StreamingVitalReplaySourceFactory


@dataclass(frozen=True)
class LabRecorderSendReceipt:
    transport: str
    bytes_sent: int


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


LabRecorderExecutionResultSink = Callable[
    [tuple[LabRecorderExecutionResult, ...]],
    None,
]
LabSessionCompletionSink = Callable[[str], None]


@dataclass
class _RunningLabSession:
    stop_event: threading.Event
    thread: threading.Thread
    active_recorder_ids: set[str]
    active_recorder_ids_lock: threading.Lock
    target_url: str
    recorder_vrcodes: dict[str, str]
    case_started_at: float
    replay_source: LabVitalReplaySource | None


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


class LabSessionStartError(Exception):
    def __init__(self, message: str, *, stage: str, code: str) -> None:
        super().__init__(message)
        self.stage = stage
        self.code = code


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


class LabExecutionEngine:
    def __init__(
        self,
        *,
        sender: LabRecorderPayloadSender,
        vital_replay_source_factory: LabVitalReplaySourceFactory | None = None,
        frame_interval_seconds: float = 1.0,
        archive_finalizer: LabRecorderArchiveFinalizer | None = None,
    ) -> None:
        self.sender = sender
        self.vital_replay_source_factory = (
            vital_replay_source_factory
            or StreamingVitalReplaySourceFactory(
                string_track_policy=LabReplayStringTrackPolicy.REJECT,
                gap_policy=LabReplayGapPolicy.OMIT_TRACK,
            )
        )
        self.frame_interval_seconds = max(0.0, frame_interval_seconds)
        self.archive_finalizer = archive_finalizer
        self._running_sessions: dict[str, _RunningLabSession] = {}
        self._running_sessions_lock = threading.Lock()

    def start_session(
        self,
        *,
        session: LabSession,
        beds: tuple[LabBed, ...],
        recorders: tuple[LabRecorder, ...],
        result_sink: LabRecorderExecutionResultSink | None = None,
        completion_sink: LabSessionCompletionSink | None = None,
    ) -> tuple[LabRecorderExecutionResult, ...]:
        self.pause_session(session.session_id)
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

        replay_source = self._open_replay_source(session)
        case_started_at = time.time()
        try:
            results = self._send_session_frame(
                session=session,
                beds_by_id=beds_by_id,
                recorders=recorders,
                sequence=1,
                frame_started_at=case_started_at,
                case_started_at=case_started_at,
                replay_source=replay_source,
            )
        except Exception:
            _close_replay_source(replay_source)
            raise
        if recorders:
            self._start_session_runner(
                session=session,
                beds_by_id=beds_by_id,
                recorders=recorders,
                active_recorder_ids={recorder.recorder_id for recorder in recorders},
                initial_sequence=2,
                case_started_at=case_started_at,
                result_sink=result_sink,
                replay_source=replay_source,
                completion_sink=completion_sink,
            )
        else:
            _close_replay_source(replay_source)
        return results

    def start_recorder(
        self,
        *,
        session: LabSession,
        beds: tuple[LabBed, ...],
        recorders: tuple[LabRecorder, ...],
        recorder_id: str,
        result_sink: LabRecorderExecutionResultSink | None = None,
        completion_sink: LabSessionCompletionSink | None = None,
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
            case_started_at = running.case_started_at
            replay_source = running.replay_source
        else:
            case_started_at = time.time()
            replay_source = self._open_replay_source(session)
        try:
            results = self._send_session_frame(
                session=session,
                beds_by_id=beds_by_id,
                recorders=(recorder,),
                sequence=1,
                frame_started_at=time.time(),
                case_started_at=case_started_at,
                replay_source=replay_source,
            )
        except Exception:
            if running is None:
                _close_replay_source(replay_source)
            raise
        if running is None:
            self._start_session_runner(
                session=session,
                beds_by_id=beds_by_id,
                recorders=recorders,
                active_recorder_ids={recorder_id},
                initial_sequence=2,
                case_started_at=case_started_at,
                result_sink=result_sink,
                replay_source=replay_source,
                completion_sink=completion_sink,
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
        return

    def pause_session(
        self,
        session_id: str,
    ) -> None:
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
        _close_replay_source(running.replay_source)
        return

    def finish_session(
        self,
        session_id: str,
        *,
        vrcodes: tuple[str, ...],
    ) -> LabArchiveFinalizationReceipt:
        """Stop execution and explicitly finalize every session-owned archive."""
        self.pause_session(session_id)
        if not vrcodes:
            raise LabArchiveFinalizationError(
                "Lab session finish requires at least one recorder vrcode."
            )
        if self.archive_finalizer is None:
            raise LabArchiveFinalizationError(
                "Lab session finish archive finalizer is unavailable."
            )
        receipt = self._request_archive_finalization(
            vrcodes=vrcodes,
            reason="lab_session_finished",
        )
        if receipt is None:
            raise LabArchiveFinalizationError(
                "Lab session finish archive finalization was not accepted."
            )
        return receipt

    def archive_finalization_progress(
        self,
        *,
        request_ids: tuple[str, ...],
    ) -> LabArchiveFinalizationProgress:
        """Read the state owned by recorder-ingress; Lab retains only its reference."""
        if self.archive_finalizer is None:
            raise LabArchiveFinalizationError(
                "Lab archive finalization status reader is unavailable."
            )
        return self.archive_finalizer.read_finalization(request_ids=request_ids)

    def shutdown(self) -> None:
        with self._running_sessions_lock:
            session_ids = tuple(self._running_sessions)
        for session_id in session_ids:
            self.pause_session(session_id)
        self.sender.close_all()

    def _request_archive_finalization(
        self,
        *,
        vrcodes: tuple[str, ...],
        reason: LabArchiveFinalizationReason,
    ) -> LabArchiveFinalizationReceipt | None:
        if self.archive_finalizer is None or not vrcodes:
            return None
        return self.archive_finalizer.request_finalization(
            vrcodes=vrcodes,
            reason=reason,
        )

    def _start_session_runner(
        self,
        *,
        session: LabSession,
        beds_by_id: dict[str, LabBed],
        recorders: tuple[LabRecorder, ...],
        active_recorder_ids: set[str],
        initial_sequence: int,
        case_started_at: float,
        result_sink: LabRecorderExecutionResultSink | None,
        replay_source: LabVitalReplaySource | None,
        completion_sink: LabSessionCompletionSink | None,
    ) -> None:
        target_url = session.target_url
        if target_url is None:
            raise LabRecorderSendError("targetURL is not configured")
        stop_event = threading.Event()
        active_recorder_ids_lock = threading.Lock()

        def run() -> None:
            sequence = initial_sequence
            while not stop_event.wait(self.frame_interval_seconds):
                if self._replay_is_complete(
                    session=session,
                    replay_source=replay_source,
                    sequence=sequence,
                ):
                    completed_vrcodes = tuple(recorder.vrcode for recorder in recorders)
                    for vrcode in completed_vrcodes:
                        self.sender.close_recorder(
                            target_url=target_url,
                            vrcode=vrcode,
                        )
                    try:
                        self._request_archive_finalization(
                            vrcodes=completed_vrcodes,
                            reason="lab_session_finished",
                        )
                    except LabArchiveFinalizationError as error:
                        print(
                            "[vitalserver-lab] recorder archive finalization failed:",
                            str(error),
                        )
                    try:
                        if completion_sink is not None:
                            completion_sink(session.session_id)
                    finally:
                        _close_replay_source(replay_source)
                        with self._running_sessions_lock:
                            current = self._running_sessions.get(session.session_id)
                            if (
                                current is not None
                                and current.thread is threading.current_thread()
                            ):
                                self._running_sessions.pop(session.session_id, None)
                    return
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
                    frame_started_at=time.time(),
                    case_started_at=case_started_at,
                    replay_source=replay_source,
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
                case_started_at=case_started_at,
                replay_source=replay_source,
            )
        if previous is not None:
            previous.stop_event.set()
            if threading.current_thread() is not previous.thread:
                previous.thread.join(timeout=2)
            _close_replay_source(previous.replay_source)
        thread.start()

    def _replay_is_complete(
        self,
        *,
        session: LabSession,
        replay_source: LabVitalReplaySource | None,
        sequence: int,
    ) -> bool:
        if replay_source is None:
            return False
        if session.replay_policy is None:
            raise LabRecorderSendError("Vital File replay policy is not configured")
        repeat_count = session.replay_policy.finite_count
        if repeat_count is None:
            return False
        return sequence > replay_source.duration_seconds * repeat_count

    def _send_session_frame(
        self,
        *,
        session: LabSession,
        beds_by_id: dict[str, LabBed],
        recorders: tuple[LabRecorder, ...],
        sequence: int,
        frame_started_at: float,
        case_started_at: float,
        replay_source: LabVitalReplaySource | None,
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
                    frame_started_at=frame_started_at,
                    case_started_at=case_started_at,
                    replay_source=replay_source,
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

    def _open_replay_source(self, session: LabSession) -> LabVitalReplaySource | None:
        if session.scenario_id != "vital-file-replay":
            return None
        if session.vital_file_path is None:
            raise LabRecorderSendError("Vital File replay source is not configured")
        try:
            return self.vital_replay_source_factory.open(Path(session.vital_file_path))
        except VitalReplaySourceError as error:
            raise LabSessionStartError(
                str(error),
                stage=error.stage,
                code=error.code,
            ) from error


def _close_replay_source(source: LabVitalReplaySource | None) -> None:
    if source is not None:
        source.close()


def lab_recorder_payload(
    *,
    session: LabSession,
    bed: LabBed,
    recorder: LabRecorder,
    sequence: int = 1,
    frame_started_at: float,
    case_started_at: float,
    replay_source: LabVitalReplaySource | None = None,
) -> dict[str, object]:
    if session.scenario_id == "vital-file-replay":
        if session.vital_file_path is None:
            raise LabRecorderSendError("vital file replay source is not configured")
        if replay_source is None:
            raise LabRecorderSendError("Vital File replay reader is not configured")
        return lab_vital_file_replay_payload(
            session=session,
            bed=bed,
            recorder=recorder,
            sequence=sequence,
            frame_started_at=frame_started_at,
            case_started_at=case_started_at,
            replay_source=replay_source,
        )

    now = frame_started_at
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
        "dtcase": case_started_at,
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
    frame_started_at: float,
    case_started_at: float,
    replay_source: LabVitalReplaySource,
) -> dict[str, object]:
    now = frame_started_at
    source_offset = (sequence - 1) % replay_source.duration_seconds
    try:
        source_frame = replay_source.frame(
            offset_seconds=source_offset,
            output_time=now,
        )
    except VitalReplaySourceError as error:
        raise LabRecorderSendError(str(error)) from error
    room = {
        "roomname": bed.name,
        "seqid": sequence,
        "dtstart": now,
        "dtend": now + 1,
        "dtcase": case_started_at,
        "dtapp": now,
        "dtserver": now,
        "ptcon": 1,
        "recording": 1,
        "devs": list(source_frame.devices),
        "trks": list(source_frame.tracks),
        "evts": [
            {
                "dt": now,
                "val": (
                    "Vital File replay source frame "
                    f"{source_offset + 1}/{replay_source.duration_seconds}"
                ),
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
