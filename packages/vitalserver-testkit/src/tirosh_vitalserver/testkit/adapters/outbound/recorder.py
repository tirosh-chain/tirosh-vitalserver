"""Outbound Socket.IO implementation for Vital Recorder realtime data."""

from __future__ import annotations

from urllib.parse import urlencode

from tirosh_vitalserver.testkit.application.ports import SocketIoClientPort


def emit_send_data(base_url: str, encoded: bytes, *, timeout: float = 30.0) -> None:
    """Open a short-lived Socket.IO connection and emit one `send_data` event."""

    client = connect_socketio(base_url, timeout=timeout)

    try:
        client.emit("send_data", encoded)
        client.sleep(0.05)
    finally:
        if client.connected:
            client.disconnect()


def connect_socketio(base_url: str, *, timeout: float = 30.0) -> SocketIoClientPort:
    """Connect a Socket.IO client to VitalServer."""

    try:
        import socketio
    except ImportError as exc:
        raise RuntimeError(
            "python-socketio is required for real-time send_data tests"
        ) from exc

    client = socketio.Client(
        reconnection=False,
        request_timeout=timeout,
        logger=False,
        engineio_logger=False,
    )
    client.connect(base_url, transports=["websocket", "polling"])

    return client


class SocketIoRecorderManagementClient:
    """VitalServer recorder management operations over Socket.IO."""

    def delete_vrecorder(
        self,
        base_url: str,
        vrcode: str,
        *,
        timeout: float = 5.0,
    ) -> None:
        client = connect_socketio(base_url, timeout=timeout)

        try:
            client.emit("req_cmd", urlencode({"job": "del_vr", "vrcode": vrcode}))
            client.sleep(0.2)
        finally:
            if client.connected:
                client.disconnect()

    def delete_bed(
        self,
        base_url: str,
        *,
        bed_id: str,
        bed_name: str,
        timeout: float = 5.0,
    ) -> None:
        client = connect_socketio(base_url, timeout=timeout)

        try:
            client.emit(
                "req_cmd",
                urlencode({"job": "del_bed", "bedid": bed_id, "bedname": bed_name}),
            )
            client.sleep(0.2)
        finally:
            if client.connected:
                client.disconnect()
