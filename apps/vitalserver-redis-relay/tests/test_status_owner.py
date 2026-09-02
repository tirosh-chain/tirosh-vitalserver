from __future__ import annotations

import json
import socket
from pathlib import Path
from threading import Event, Thread
from typing import Any
from uuid import uuid4

import pytest

from vitalserver_redis_relay.status_owner import (
    HttpStatusOwnerPublisher,
    UnixSocketStatusOwnerPublisher,
)
from vitalserver_redis_relay.status_publisher import StatusPublisherConfigurationError


class FakeResponse:
    def __init__(self, status: int) -> None:
        self.status = status

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *args: object) -> None:
        return None


def test_http_status_owner_publisher_puts_status_document(monkeypatch: Any) -> None:
    requests: list[Any] = []

    def fake_urlopen(request: Any, timeout: float) -> FakeResponse:
        requests.append((request, timeout))
        return FakeResponse(200)

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)

    result = HttpStatusOwnerPublisher(
        owner_url="http://guest-control:18330/runtime/redis-relay/status",
        timeout_seconds=2.0,
    ).publish({"observedAt": "2026-07-01T00:00:00Z", "state": "running"})

    assert result.any_published is True
    assert result.outcomes[0].publisher == "http"
    assert result.outcomes[0].error is None
    request, timeout = requests[0]
    assert request.full_url == "http://guest-control:18330/runtime/redis-relay/status"
    assert request.get_method() == "PUT"
    assert timeout == 2.0
    assert json.loads(request.data.decode("utf-8")) == {
        "observedAt": "2026-07-01T00:00:00Z",
        "state": "running",
    }


def test_http_status_owner_publisher_rejects_empty_url() -> None:
    with pytest.raises(StatusPublisherConfigurationError, match="must not be empty"):
        HttpStatusOwnerPublisher(owner_url="  ")


def test_http_status_owner_publisher_rejects_malformed_url() -> None:
    with pytest.raises(StatusPublisherConfigurationError, match="is invalid") as error:
        HttpStatusOwnerPublisher(owner_url="not-a-url")

    assert "not-a-url" not in str(error.value)
    assert error.value.__cause__ is None


def test_http_status_owner_publisher_rejects_unsupported_scheme() -> None:
    with pytest.raises(
        StatusPublisherConfigurationError,
        match="scheme must be http or https",
    ) as error:
        HttpStatusOwnerPublisher(owner_url="ftp://user:secret@example.test/status")

    message = str(error.value)
    assert "ftp://" not in message
    assert "secret" not in message
    assert "example.test" not in message
    assert error.value.__cause__ is None


def test_http_status_owner_publisher_rejects_missing_host() -> None:
    with pytest.raises(StatusPublisherConfigurationError, match="host is required"):
        HttpStatusOwnerPublisher(owner_url="http:///runtime/redis-relay/status")


def test_http_status_owner_publisher_rejects_invalid_port() -> None:
    with pytest.raises(
        StatusPublisherConfigurationError,
        match="port is invalid",
    ) as error:
        HttpStatusOwnerPublisher(
            owner_url="http://guest-control:99999/runtime/redis-relay/status"
        )

    assert "99999" not in str(error.value)
    assert "guest-control" not in str(error.value)
    assert error.value.__cause__ is None


def test_http_status_owner_publisher_accepts_https_url(monkeypatch: Any) -> None:
    requests: list[Any] = []

    def fake_urlopen(request: Any, timeout: float) -> FakeResponse:
        requests.append((request, timeout))
        return FakeResponse(200)

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    document = {"observedAt": "2026-07-01T00:00:00Z", "state": "running"}

    result = HttpStatusOwnerPublisher(
        owner_url="https://guest-control:18330/runtime/redis-relay/status",
        timeout_seconds=2.0,
    ).publish(document)

    assert result.any_published is True
    request, timeout = requests[0]
    assert request.full_url == (
        "https://guest-control:18330/runtime/redis-relay/status"
    )
    assert request.get_method() == "PUT"
    assert timeout == 2.0
    assert json.loads(request.data.decode("utf-8")) == document


def test_unix_status_owner_publisher_puts_status_document_over_unix_socket() -> None:
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

        result = UnixSocketStatusOwnerPublisher(
            owner_socket_path=socket_path,
            timeout_seconds=1,
        ).publish(document)

        thread.join(timeout=1)
        assert not thread.is_alive()
        assert result.any_published is True
        assert result.outcomes[0].publisher == "unix-socket"
        assert request[0].startswith(
            b"PUT /runtime/redis-relay/status HTTP/1.1\r\n"
        )
        assert json.loads(request[0].split(b"\r\n\r\n", 1)[1]) == document
    finally:
        socket_path.unlink(missing_ok=True)
