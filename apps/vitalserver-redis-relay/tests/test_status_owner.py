from __future__ import annotations

import json
import socket
from pathlib import Path
from threading import Event, Thread
from typing import Any
from uuid import uuid4

import pytest

from vitalserver_redis_relay.status_owner import (
    GuestControlStatusOwnerPublisher,
    StatusOwnerConfigurationError,
)


class FakeResponse:
    def __init__(self, status: int) -> None:
        self.status = status

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *args: object) -> None:
        return None


def test_status_owner_publisher_puts_status_document(monkeypatch) -> None:
    requests: list[Any] = []

    def fake_urlopen(request, timeout: float) -> FakeResponse:
        requests.append((request, timeout))
        return FakeResponse(200)

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)

    result = GuestControlStatusOwnerPublisher(
        owner_url="http://guest-control:18330/runtime/redis-relay/status",
        timeout_seconds=2.0,
    ).publish({"observedAt": "2026-07-01T00:00:00Z", "state": "running"})

    assert result.published is True
    assert result.error is None
    request, timeout = requests[0]
    assert request.full_url == "http://guest-control:18330/runtime/redis-relay/status"
    assert request.get_method() == "PUT"
    assert timeout == 2.0
    assert json.loads(request.data.decode("utf-8")) == {
        "observedAt": "2026-07-01T00:00:00Z",
        "state": "running",
    }


def test_status_owner_publisher_requires_exactly_one_transport(tmp_path: Path) -> None:
    with pytest.raises(StatusOwnerConfigurationError) as error:
        GuestControlStatusOwnerPublisher(owner_url="")

    assert str(error.value) == (
        "Exactly one Redis relay status owner URL or socket path is required."
    )

    with pytest.raises(StatusOwnerConfigurationError):
        GuestControlStatusOwnerPublisher(
            owner_url="http://guest-control:18330/runtime/redis-relay/status",
            owner_socket_path=tmp_path / "owner.sock",
        )


def test_status_owner_publisher_puts_status_document_over_unix_socket() -> None:
    if not hasattr(socket, "AF_UNIX"):
        pytest.skip("Unix domain sockets are unavailable on this platform")
    socket_path = Path("/tmp") / f"vitalserver-status-owner-{uuid4().hex}.sock"
    ready = Event()
    request: list[bytes] = []

    def serve_once() -> None:
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            server.bind(str(socket_path))
            server.listen(1)
            ready.set()
            connection, _ = server.accept()
            with connection:
                received = b""
                while b"\r\n\r\n" not in received:
                    received += connection.recv(4096)
                headers, body = received.split(b"\r\n\r\n", 1)
                content_length = next(
                    int(line.split(b":", 1)[1].strip())
                    for line in headers.split(b"\r\n")
                    if line.lower().startswith(b"content-length:")
                )
                while len(body) < content_length:
                    body += connection.recv(4096)
                request.append(headers + b"\r\n\r\n" + body)
                connection.sendall(
                    b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
                )
        finally:
            server.close()

    try:
        thread = Thread(target=serve_once, daemon=True)
        thread.start()
        assert ready.wait(timeout=1)
        document = {"observedAt": "2026-07-01T00:00:00Z", "state": "running"}

        result = GuestControlStatusOwnerPublisher(
            owner_socket_path=socket_path,
            timeout_seconds=1,
        ).publish(document)

        thread.join(timeout=1)
        assert not thread.is_alive()
        assert result.published is True
        assert request[0].startswith(
            b"PUT /runtime/redis-relay/status HTTP/1.1\r\n"
        )
        assert json.loads(request[0].split(b"\r\n\r\n", 1)[1]) == document
    finally:
        socket_path.unlink(missing_ok=True)
