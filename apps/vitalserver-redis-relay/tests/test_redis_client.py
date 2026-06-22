from __future__ import annotations

from typing import Any

from vitalserver_redis_relay.redis_client import RedisClient
from vitalserver_redis_relay.replication import (
    KeyType,
    RedisKeySnapshot,
    TargetPublishStatus,
)
from vitalserver_redis_relay.settings import RedisEndpoint, RelayPublishContract


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

    client = RedisClient(
        RedisEndpoint(
            host="target",
            port=6379,
            database=2,
            username="default",
            password="secret",
        )
    )

    with client.session() as session:
        assert session.command("PING") == "PONG"

    assert len(sockets) == 1
    assert b"AUTH" in sockets[0].sent[0]
    assert b"default" in sockets[0].sent[0]
    assert b"secret" in sockets[0].sent[0]
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


def _array_response(values: list[str]) -> bytes:
    chunks = [f"*{len(values)}\r\n".encode()]
    for value in values:
        raw = value.encode()
        chunks.append(f"${len(raw)}\r\n".encode())
        chunks.append(raw)
        chunks.append(b"\r\n")
    return b"".join(chunks)
