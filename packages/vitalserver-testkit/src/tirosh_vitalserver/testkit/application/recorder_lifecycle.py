"""Vital Recorder compatible Socket.IO lifecycle helpers."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from tirosh_vitalserver.testkit.application.ports import SocketIoClientPort
from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeState,
)

MANAGEMENT_EVENTS = (
    "update",
    "restart",
    "reboot",
    "del_bed",
    "add_event",
    "edit_bed",
    "edit_conf",
)


def register_vrecorder_lifecycle(
    client: SocketIoClientPort,
    *,
    state: RecorderRuntimeState,
) -> None:
    """Register lifecycle handlers and emit `join_vr`.

    The current adapter connects before handlers are registered. We still attach a
    `connect` handler so a future reconnect-capable adapter can re-send
    `join_vr` after reconnect.
    """

    def emit_join() -> None:
        client.emit("join_vr", state.vrcode)
        state.mark_join_sent()

    def on_connect() -> None:
        state.mark_connected()
        emit_join()

    client.on("connect", lambda *args: on_connect())
    client.on("disconnect", lambda *args: state.mark_disconnected())
    client.on("dt", state.record_server_dt)

    for event_name in MANAGEMENT_EVENTS:
        client.on(event_name, management_event_handler(state, event_name))

    if client.connected:
        state.mark_connected()
        emit_join()


def management_event_handler(
    state: RecorderRuntimeState,
    event_name: str,
) -> Callable[..., None]:
    """Build a Socket.IO handler that records one management event."""

    def handler(*payload: Any) -> None:
        state.record_management_event(event_name, payload)

    return handler
