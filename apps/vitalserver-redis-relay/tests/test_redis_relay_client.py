from __future__ import annotations

from typing import Any

import pytest

from vitalserver_redis_relay.key_filter import RelayScope
from vitalserver_redis_relay.redis_client import (
    RedisAuthenticationError,
    RedisClient,
)
from vitalserver_redis_relay.replication import (
    KeyType,
    RedisKeySnapshot,
    TargetPublishStatus,
)
from vitalserver_redis_relay.settings import (
    RedisEndpoint,
    RelayPublishContract,
    RelaySettings,
    default_publish_contract,
)
from vitalserver_redis_relay.status import build_status_document


class FakeSocket:
    def __init__(self, responses: bytes) -> None:
        self.responses = bytearray(responses)
        self.sent: list[bytes] = []
        self.closed = False
        self.timeout: float | None = None

    def settimeout(self, timeout: float) -> None:
        self.timeout = timeout

    def sendall(self, data: bytes) -> None:
        self.sent.append(data)

    def recv(self, length: int) -> bytes:
        chunk = self.responses[:length]
        del self.responses[:length]
        return bytes(chunk)

    def close(self) -> None:
        self.closed = True


def test_session_reuses_one_socket_for_multiple_commands(monkeypatch: Any) -> None:
    sockets: list[FakeSocket] = []

    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        assert address == ("target", 6379)
        assert timeout == 2.0
        socket = FakeSocket(b"+PONG\r\n$2\r\nok\r\n")
        sockets.append(socket)
        return socket

    monkeypatch.setattr(
        "vitalserver_redis_relay.redis_client.socket.create_connection",
        create_connection,
    )

    client = RedisClient(RedisEndpoint(host="target", port=6379, database=0))

    with client.session() as session:
        assert session.command("PING") == "PONG"
        assert session.command("ECHO", "ok") == "ok"

    assert len(sockets) == 1
    assert sockets[0].closed is True
    assert b"PING" in sockets[0].sent[0]
    assert b"ECHO" in sockets[0].sent[1]


def test_session_authenticates_and_selects_database_once(monkeypatch: Any) -> None:
    sockets: list[FakeSocket] = []

    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        socket = FakeSocket(b"+OK\r\n+OK\r\n+PONG\r\n")
        sockets.append(socket)
        return socket

    monkeypatch.setattr(
        "vitalserver_redis_relay.redis_client.socket.create_connection",
        create_connection,
    )

    username = "default"
    password = "secret"
    client = RedisClient(
        RedisEndpoint(
            host="target",
            port=6379,
            database=2,
            username=username,
            password=password,
        )
    )

    with client.session() as session:
        assert session.command("PING") == "PONG"

    assert len(sockets) == 1
    _assert_auth_command(
        sockets[0].sent[0],
        username=username,
        password=password,
    )
    assert b"SELECT" in sockets[0].sent[1]
    assert b"2" in sockets[0].sent[1]
    assert b"PING" in sockets[0].sent[2]


def test_session_reconnects_and_retries_command_after_closed_connection(
    monkeypatch: Any,
) -> None:
    sockets: list[FakeSocket] = []
    sleeps: list[float] = []

    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        socket = FakeSocket(b"" if not sockets else b"+PONG\r\n")
        sockets.append(socket)
        return socket

    monkeypatch.setattr(
        "vitalserver_redis_relay.redis_client.socket.create_connection",
        create_connection,
    )

    client = RedisClient(
        RedisEndpoint(host="target", port=6379, database=0),
        retry_sleep=sleeps.append,
    )

    with client.session() as session:
        assert session.command("PING") == "PONG"

    assert len(sockets) == 2
    assert sockets[0].closed is True
    assert b"PING" in sockets[0].sent[0]
    assert b"PING" in sockets[1].sent[0]
    assert sleeps == [0.25]


def test_session_retries_initial_connection_failure(monkeypatch: Any) -> None:
    attempts = 0
    sockets: list[FakeSocket] = []
    sleeps: list[float] = []

    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise TimeoutError("target connect timed out")
        socket = FakeSocket(b"+PONG\r\n")
        sockets.append(socket)
        return socket

    monkeypatch.setattr(
        "vitalserver_redis_relay.redis_client.socket.create_connection",
        create_connection,
    )

    client = RedisClient(
        RedisEndpoint(host="target", port=6379, database=0),
        retry_sleep=sleeps.append,
    )

    with client.session() as session:
        assert session.command("PING") == "PONG"

    assert attempts == 2
    assert len(sockets) == 1
    assert sleeps == [0.25]


def test_publish_snapshot_if_changed_uses_atomic_protocol_script(
    monkeypatch: Any,
) -> None:
    sockets: list[FakeSocket] = []

    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        socket = FakeSocket(_array_response(["published", "mirror:wave-key", "1-0"]))
        sockets.append(socket)
        return socket

    monkeypatch.setattr(
        "vitalserver_redis_relay.redis_client.socket.create_connection",
        create_connection,
    )

    client = RedisClient(
        RedisEndpoint(host="target", port=6379, database=0),
        publish_contract=RelayPublishContract(
            target_key_prefix="mirror:",
            event_stream_key="mirror:events",
            fingerprint_hash_key="mirror:fingerprints",
            publish_dedupe_hash_key="mirror:published",
            event_stream_maxlen=1000,
            publisher_id="helper-test",
        ),
    )

    with client.session() as session:
        result = session.publish_snapshot_if_changed(
            RedisKeySnapshot(
                key="wave-key",
                key_type=KeyType.STRING,
                ttl_ms=-1,
                serialized_payload=b"redis-dump-payload",
            )
        )

    assert result.source_key == "wave-key"
    assert result.target_key == "mirror:wave-key"
    assert result.status == TargetPublishStatus.PUBLISHED
    assert result.event_id == "1-0"
    assert len(sockets[0].sent) == 1
    command = sockets[0].sent[0]
    assert b"EVAL" in command
    assert b"mirror:wave-key" in command
    assert b"mirror:events" in command
    assert b"mirror:fingerprints" in command
    assert b"mirror:published" in command
    assert b"helper-test" in command
    assert b"redis-dump-payload" in command


AUTH_USERNAME = "relay-user"
AUTH_PASSWORD = "sentinel-password"


def test_source_password_auth_failure_does_not_expose_credentials(
    monkeypatch: Any,
) -> None:
    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        del address, timeout
        return FakeSocket(
            b"-ERR invalid password sentinel-password\r\n"
        )

    monkeypatch.setattr(
        "vitalserver_redis_relay.redis_client.socket.create_connection",
        create_connection,
    )
    client = RedisClient(
        RedisEndpoint(host="redis", port=6379, database=0, password=AUTH_PASSWORD)
    )

    with (
        pytest.raises(
            RedisAuthenticationError,
            match="Redis authentication failed",
        ) as error,
        client.session(),
    ):
        pass

    assert AUTH_PASSWORD not in str(error.value)
    assert AUTH_PASSWORD not in repr(error.value)
    assert error.value.__cause__ is None


def test_target_username_password_auth_failure_does_not_expose_credentials(
    monkeypatch: Any,
) -> None:
    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        del address, timeout
        return FakeSocket(
            b"-WRONGPASS user relay-user password sentinel-password\r\n"
        )

    monkeypatch.setattr(
        "vitalserver_redis_relay.redis_client.socket.create_connection",
        create_connection,
    )
    client = RedisClient(
        RedisEndpoint(
            host="target",
            port=6379,
            database=0,
            username=AUTH_USERNAME,
            password=AUTH_PASSWORD,
        )
    )

    with (
        pytest.raises(
            RedisAuthenticationError,
            match="Redis authentication failed",
        ) as error,
        client.session(),
    ):
        pass

    message = str(error.value)
    assert AUTH_USERNAME not in message
    assert AUTH_PASSWORD not in message
    assert AUTH_USERNAME not in repr(error.value)
    assert AUTH_PASSWORD not in repr(error.value)
    assert error.value.__cause__ is None


def test_auth_connection_close_still_retries(monkeypatch: Any) -> None:
    sockets: list[FakeSocket] = []
    sleeps: list[float] = []

    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        del address, timeout
        socket = FakeSocket(b"" if not sockets else b"+OK\r\n+PONG\r\n")
        sockets.append(socket)
        return socket

    monkeypatch.setattr(
        "vitalserver_redis_relay.redis_client.socket.create_connection",
        create_connection,
    )
    client = RedisClient(
        RedisEndpoint(host="redis", port=6379, database=0, password=AUTH_PASSWORD),
        retry_sleep=sleeps.append,
    )

    with client.session() as session:
        assert session.command("PING") == "PONG"

    assert len(sockets) == 2
    assert sleeps == [0.25]


def test_authentication_failure_status_does_not_include_credentials() -> None:
    error = RedisAuthenticationError("Redis authentication failed")
    document = build_status_document(
        settings=RelaySettings(
            enabled=True,
            source=RedisEndpoint(
                host="redis",
                port=6379,
                database=0,
                password=AUTH_PASSWORD,
            ),
            target=RedisEndpoint(
                host="target",
                port=6379,
                database=0,
                username=AUTH_USERNAME,
                password=AUTH_PASSWORD,
            ),
            publish_contract=default_publish_contract(),
            scope=RelayScope.VITAL_RECONSTRUCTION,
            include_recorder_network_context=False,
            interval_seconds=1.0,
            scan_count=1000,
            status_interval_seconds=5.0,
        ),
        state="relay_failed",
        error=str(error),
    )

    assert document["lastError"] == "Redis authentication failed"
    assert AUTH_USERNAME not in str(document)
    assert AUTH_PASSWORD not in str(document)


def _assert_auth_command(
    payload: bytes,
    *,
    username: str | None,
    password: str,
) -> None:
    try:
        parts = _resp_bulk_strings(payload)
    except ValueError:
        raise AssertionError("AUTH command is not a valid RESP array") from None
    expected: tuple[bytes, ...]
    if username is None:
        expected = (b"AUTH", password.encode())
    else:
        expected = (b"AUTH", username.encode(), password.encode())
    if parts != expected:
        raise AssertionError("AUTH command did not use the configured credentials")


def _resp_bulk_strings(payload: bytes) -> tuple[bytes, ...]:
    if not payload.startswith(b"*"):
        raise ValueError("not a RESP array")
    rest = payload[1:]
    header, _, remainder = rest.partition(b"\r\n")
    count = int(header)
    parts: list[bytes] = []
    cursor = remainder
    for _ in range(count):
        if not cursor.startswith(b"$"):
            raise ValueError("not a bulk string")
        size_line, _, cursor = cursor[1:].partition(b"\r\n")
        size = int(size_line)
        part = cursor[:size]
        cursor = cursor[size:]
        if not cursor.startswith(b"\r\n"):
            raise ValueError("truncated bulk string")
        cursor = cursor[2:]
        parts.append(part)
    return tuple(parts)


def _array_response(values: list[str]) -> bytes:
    chunks = [f"*{len(values)}\r\n".encode()]
    for value in values:
        raw = value.encode()
        chunks.append(f"${len(raw)}\r\n".encode())
        chunks.append(raw)
        chunks.append(b"\r\n")
    return b"".join(chunks)
