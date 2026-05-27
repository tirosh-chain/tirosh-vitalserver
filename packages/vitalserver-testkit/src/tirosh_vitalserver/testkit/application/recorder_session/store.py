"""Persistence boundary for virtual VRecorder session registry."""

from __future__ import annotations

from dataclasses import asdict
from typing import Any, Protocol

from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderManagementEvent,
    RecorderRuntimeSnapshot,
)
from tirosh_vitalserver.testkit.application.recorder_session.models import (
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionSnapshot,
    VirtualRecorderSessionState,
)
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario


class VirtualRecorderSessionStorePort(Protocol):
    """Persistent registry for virtual VRecorder session snapshots."""

    def load_sessions(self) -> tuple[VirtualRecorderSessionSnapshot, ...]: ...

    def save_session(self, snapshot: VirtualRecorderSessionSnapshot) -> None: ...

    def delete_session(self, session_id: str) -> None: ...

    def delete_all_sessions(self) -> None: ...


def session_snapshot_to_record(
    snapshot: VirtualRecorderSessionSnapshot,
) -> dict[str, Any]:
    """Convert a session snapshot into a persistent JSON record."""

    data = asdict(snapshot)
    data["state"] = snapshot.state.value
    data["request"]["default_scenario"] = snapshot.request.default_scenario.value
    data["recorders"] = [
        recorder_snapshot_to_record(recorder)
        for recorder in snapshot.recorders
    ]

    return data


def session_snapshot_from_record(
    data: dict[str, Any],
) -> VirtualRecorderSessionSnapshot:
    """Convert a persistent JSON record into a session snapshot."""

    request_data = dict(data["request"])
    request_data["default_scenario"] = RecorderSignalScenario(
        request_data.get("default_scenario", RecorderSignalScenario.NORMAL.value)
    )

    return VirtualRecorderSessionSnapshot(
        session_id=str(data["session_id"]),
        state=VirtualRecorderSessionState(str(data["state"])),
        request=VirtualRecorderSessionRequest(**request_data),
        created_at=float(data["created_at"]),
        started_at=optional_float(data.get("started_at")),
        stopped_at=optional_float(data.get("stopped_at")),
        recorders=tuple(
            recorder_snapshot_from_record(recorder)
            for recorder in data.get("recorders", [])
        ),
        messages_sent=int(data.get("messages_sent", 0)),
        bytes_sent=int(data.get("bytes_sent", 0)),
        error=data.get("error"),
    )


def recorder_snapshot_to_record(snapshot: RecorderRuntimeSnapshot) -> dict[str, Any]:
    """Convert a recorder runtime snapshot into a persistent JSON record."""

    data = asdict(snapshot)
    data["management_events"] = [
        {
            "name": event.name,
            "received_at": event.received_at,
            "payload": list(event.payload),
        }
        for event in snapshot.management_events
    ]

    return data


def recorder_snapshot_from_record(data: dict[str, Any]) -> RecorderRuntimeSnapshot:
    """Convert a persistent JSON record into a recorder runtime snapshot."""

    return RecorderRuntimeSnapshot(
        vrcode=str(data["vrcode"]),
        base_url=str(data["base_url"]),
        local_ip=data.get("local_ip"),
        connected=bool(data.get("connected", False)),
        join_sent=bool(data.get("join_sent", False)),
        joined_at=optional_float(data.get("joined_at")),
        server_dt=data.get("server_dt"),
        server_dt_received_at=optional_float(data.get("server_dt_received_at")),
        last_reconnect_at=optional_float(data.get("last_reconnect_at")),
        last_send_data_at=optional_float(data.get("last_send_data_at")),
        messages_sent=int(data.get("messages_sent", 0)),
        bytes_sent=int(data.get("bytes_sent", 0)),
        management_events=tuple(
            RecorderManagementEvent(
                name=str(event["name"]),
                received_at=float(event["received_at"]),
                payload=tuple(event.get("payload", [])),
            )
            for event in data.get("management_events", [])
        ),
    )


def optional_float(value: Any) -> float | None:
    """Return `value` as float when present."""

    return None if value is None else float(value)
