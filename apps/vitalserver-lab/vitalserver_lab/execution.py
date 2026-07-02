from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen

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


class LabRecorderPayloadSender(Protocol):
    def send(
        self,
        *,
        target_url: str,
        payload: dict[str, object],
    ) -> LabRecorderSendReceipt:
        """Send one Vital Recorder payload to a VitalServer-compatible endpoint."""


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


class LabExecutionEngine:
    def __init__(self, *, sender: LabRecorderPayloadSender) -> None:
        self.sender = sender

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
