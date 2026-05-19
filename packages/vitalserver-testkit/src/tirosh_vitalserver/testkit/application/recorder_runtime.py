"""Runtime state for simulated Vital Recorder sessions."""

from __future__ import annotations

import socket
import threading
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlparse


@dataclass(frozen=True)
class RecorderManagementEvent:
    """One management event received from VitalServer."""

    name: str
    received_at: float
    payload: tuple[Any, ...]


@dataclass(frozen=True)
class RecorderRuntimeSnapshot:
    """Serializable snapshot of one recorder runtime state."""

    vrcode: str
    base_url: str
    local_ip: str | None
    connected: bool
    join_sent: bool
    joined_at: float | None
    server_dt: Any | None
    server_dt_received_at: float | None
    last_reconnect_at: float | None
    last_send_data_at: float | None
    messages_sent: int
    bytes_sent: int
    management_events: tuple[RecorderManagementEvent, ...]


class ConnectionRuntime:
    """Connection and registration state for one Socket.IO session."""

    def __init__(self) -> None:
        self.connected = False
        self.join_sent = False
        self.joined_at: float | None = None
        self.server_dt: Any | None = None
        self.server_dt_received_at: float | None = None
        self.last_reconnect_at: float | None = None

    def mark_connected(self) -> None:
        """Record that the Socket.IO connection is up."""

        self.connected = True
        self.last_reconnect_at = current_timestamp()

    def mark_disconnected(self) -> None:
        """Record that the Socket.IO connection is down."""

        self.connected = False

    def mark_join_sent(self) -> None:
        """Record a `join_vr` emit."""

        self.join_sent = True
        self.joined_at = current_timestamp()

    def record_server_dt(self, value: Any) -> None:
        """Record the server time returned by VitalServer."""

        self.server_dt = value
        self.server_dt_received_at = current_timestamp()


class SendDataRuntime:
    """Streaming send_data counters for one recorder."""

    def __init__(self) -> None:
        self.last_send_data_at: float | None = None
        self.messages_sent = 0
        self.bytes_sent = 0

    def record_send_data(self, *, bytes_sent: int) -> None:
        """Record one `send_data` emit."""

        self.messages_sent += 1
        self.bytes_sent += bytes_sent
        self.last_send_data_at = current_timestamp()


class ManagementEventRuntime:
    """Management event history for one recorder."""

    def __init__(self) -> None:
        self._events: list[RecorderManagementEvent] = []

    def record_management_event(self, name: str, payload: tuple[Any, ...]) -> None:
        """Record a management event received from VitalServer."""

        self._events.append(
            RecorderManagementEvent(
                name=name,
                received_at=current_timestamp(),
                payload=payload,
            )
        )

    def snapshot(self) -> tuple[RecorderManagementEvent, ...]:
        """Return a stable copy of received management events."""

        return tuple(self._events)


class RecorderRuntimeState:
    """Mutable runtime state for one simulated Vital Recorder."""

    def __init__(
        self,
        *,
        vrcode: str,
        base_url: str,
        local_ip: str | None = None,
    ) -> None:
        self.vrcode = vrcode
        self.base_url = base_url
        self.local_ip = local_ip
        self.connection = ConnectionRuntime()
        self.sender = SendDataRuntime()
        self.management = ManagementEventRuntime()
        self._lock = threading.Lock()

    def mark_connected(self) -> None:
        """Record that the Socket.IO connection is up."""

        with self._lock:
            self.connection.mark_connected()

    def mark_disconnected(self) -> None:
        """Record that the Socket.IO connection is down."""

        with self._lock:
            self.connection.mark_disconnected()

    def mark_join_sent(self) -> None:
        """Record a `join_vr` emit."""

        with self._lock:
            self.connection.mark_join_sent()

    def record_server_dt(self, value: Any) -> None:
        """Record the server time returned by VitalServer."""

        with self._lock:
            self.connection.record_server_dt(value)

    def record_send_data(self, *, bytes_sent: int) -> None:
        """Record one `send_data` emit."""

        with self._lock:
            self.sender.record_send_data(bytes_sent=bytes_sent)

    def record_management_event(self, name: str, payload: tuple[Any, ...]) -> None:
        """Record a management event received from VitalServer."""

        with self._lock:
            self.management.record_management_event(name, payload)

    def snapshot(self) -> RecorderRuntimeSnapshot:
        """Return a stable copy of the runtime state."""

        with self._lock:
            return RecorderRuntimeSnapshot(
                vrcode=self.vrcode,
                base_url=self.base_url,
                local_ip=self.local_ip,
                connected=self.connection.connected,
                join_sent=self.connection.join_sent,
                joined_at=self.connection.joined_at,
                server_dt=self.connection.server_dt,
                server_dt_received_at=self.connection.server_dt_received_at,
                last_reconnect_at=self.connection.last_reconnect_at,
                last_send_data_at=self.sender.last_send_data_at,
                messages_sent=self.sender.messages_sent,
                bytes_sent=self.sender.bytes_sent,
                management_events=self.management.snapshot(),
            )


class RecorderRuntimeRegistry:
    """Thread-safe registry for streaming recorder runtime states."""

    def __init__(self) -> None:
        self._states: dict[str, RecorderRuntimeState] = {}
        self._lock = threading.Lock()

    def state_for(self, *, vrcode: str, base_url: str) -> RecorderRuntimeState:
        """Return or create runtime state for one recorder code."""

        with self._lock:
            state = self._states.get(vrcode)
            if state is not None:
                return state

        state = RecorderRuntimeState(
            vrcode=vrcode,
            base_url=base_url,
            local_ip=local_ip_for_target(base_url),
        )

        with self._lock:
            return self._states.setdefault(vrcode, state)

    def snapshots(self) -> tuple[RecorderRuntimeSnapshot, ...]:
        """Return snapshots for every registered recorder."""

        with self._lock:
            states = tuple(self._states.values())

        return tuple(state.snapshot() for state in states)


def current_timestamp() -> float:
    """Return the current Unix timestamp used by runtime state records."""

    return time.time()


def local_ip_for_target(base_url: str) -> str | None:
    """Return the local IP used to reach a VitalServer URL when discoverable."""

    parsed = urlparse(base_url)
    host = parsed.hostname
    if host is None:
        return None
    port = parsed.port or (443 if parsed.scheme == "https" else 80)

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        try:
            sock.connect((host, port))
            return str(sock.getsockname()[0])
        except OSError:
            return None
