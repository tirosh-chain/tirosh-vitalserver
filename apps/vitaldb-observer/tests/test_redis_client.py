from __future__ import annotations

from typing import Any

import pytest

from vitaldb_observer.redis_client import (
    RedisAuthenticationError,
    RedisClient,
    RedisCommandError,
    RedisConnectionError,
    RedisEndpoint,
    RedisProtocolError,
)

SENTINEL_PASSWORD = "observer-sentinel-password-not-for-logs"


def assert_no_secret(payload: str) -> None:
    if SENTINEL_PASSWORD in payload:
        raise AssertionError("secret value leaked")


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

    def __enter__(self) -> FakeSocket:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()


def command_verb(payload: bytes) -> str:
    parts = payload.split(b"\r\n")
    return parts[2].decode()


def patch_connection(monkeypatch: Any, responses: bytes) -> list[FakeSocket]:
    sockets: list[FakeSocket] = []

    def create_connection(address: tuple[str, int], timeout: float) -> FakeSocket:
        del address, timeout
        socket = FakeSocket(responses if not sockets else b"")
        sockets.append(socket)
        return socket

    monkeypatch.setattr(
        "vitaldb_observer.redis_client.socket.create_connection",
        create_connection,
    )
    return sockets


class FakeRedisClient(RedisClient):
    response_mode = "valid"

    def __init__(self) -> None:
        self.commands: list[tuple[str, ...]] = []

    def command(self, *parts: str) -> Any:
        self.commands.append(parts)
        if self.response_mode == "wrong-type":
            return "wrong-type"
        if parts[0] == "LRANGE":
            if self.response_mode == "non-string-item":
                return ["a", 1]
            return ["a", "b"]
        if self.response_mode == "malformed-scan":
            return ["7"]
        if self.response_mode == "scan-non-string-key":
            return ["0", ["ip_A", 1]]
        cursor = parts[1]
        if cursor == "0":
            return ["7", ["ip_A", "ip_B"]]
        return ["0", ["ip_B", "ip_C"]]


def test_scan_collects_unique_keys_without_keys_command() -> None:
    client = FakeRedisClient()

    assert client.scan("ip_*", count=2) == ["ip_A", "ip_B", "ip_C"]
    assert client.commands == [
        ("SCAN", "0", "MATCH", "ip_*", "COUNT", "2"),
        ("SCAN", "7", "MATCH", "ip_*", "COUNT", "2"),
    ]


def test_lrange_returns_string_values() -> None:
    client = FakeRedisClient()

    assert client.lrange("events", -2, -1) == ["a", "b"]
    assert client.commands == [("LRANGE", "events", "-2", "-1")]


def test_lrange_rejects_non_list_response() -> None:
    client = FakeRedisClient()
    client.response_mode = "wrong-type"

    with pytest.raises(RedisProtocolError, match="unexpected LRANGE response"):
        client.lrange("events", -2, -1)


def test_lrange_rejects_non_string_items() -> None:
    client = FakeRedisClient()
    client.response_mode = "non-string-item"

    with pytest.raises(RedisProtocolError, match="unexpected LRANGE item"):
        client.lrange("events", -2, -1)


def test_smembers_rejects_non_list_response() -> None:
    client = FakeRedisClient()
    client.response_mode = "wrong-type"

    with pytest.raises(RedisProtocolError, match="unexpected SMEMBERS response"):
        client.smembers("vrs")


def test_scan_rejects_malformed_response() -> None:
    client = FakeRedisClient()
    client.response_mode = "malformed-scan"

    with pytest.raises(RedisProtocolError, match="unexpected SCAN response"):
        client.scan("ip_*", count=2)


def test_scan_rejects_non_string_keys() -> None:
    client = FakeRedisClient()
    client.response_mode = "scan-non-string-key"

    with pytest.raises(RedisProtocolError, match="unexpected SCAN key"):
        client.scan("ip_*", count=2)


def test_endpoint_repr_hides_password() -> None:
    endpoint = RedisEndpoint(
        host="127.0.0.1",
        port=6379,
        timeout_seconds=2.0,
        database=0,
        password=SENTINEL_PASSWORD,
    )
    rendered = repr(endpoint)
    assert "password_configured=True" in rendered
    assert_no_secret(rendered)
    from dataclasses import asdict

    assert_no_secret(str(asdict(endpoint)))
    if endpoint.password != SENTINEL_PASSWORD:
        raise AssertionError("endpoint did not retain the configured password")


def test_command_with_password_sends_auth_then_select_zero_then_command(
    monkeypatch: Any,
) -> None:
    sockets = patch_connection(monkeypatch, b"+OK\r\n+OK\r\n+PONG\r\n")
    client = RedisClient(
        RedisEndpoint(
            host="127.0.0.1",
            port=6379,
            timeout_seconds=2.0,
            database=0,
            password=SENTINEL_PASSWORD,
        )
    )

    assert client.ping() is True
    verbs = [command_verb(payload) for payload in sockets[0].sent]
    assert verbs == ["AUTH", "SELECT", "PING"]
    assert b"0" in sockets[0].sent[1]


def test_command_without_password_selects_then_runs_command(
    monkeypatch: Any,
) -> None:
    sockets = patch_connection(monkeypatch, b"+OK\r\n$3\r\nabc\r\n")
    client = RedisClient(
        RedisEndpoint(host="127.0.0.1", port=6379, timeout_seconds=2.0, database=0)
    )

    assert client.get("ip_A") == "abc"
    verbs = [command_verb(payload) for payload in sockets[0].sent]
    assert verbs == ["SELECT", "GET"]


def test_command_selects_nonzero_database(monkeypatch: Any) -> None:
    sockets = patch_connection(monkeypatch, b"+OK\r\n+OK\r\n+PONG\r\n")
    client = RedisClient(
        RedisEndpoint(
            host="127.0.0.1",
            port=6379,
            timeout_seconds=2.0,
            database=2,
            password=SENTINEL_PASSWORD,
        )
    )

    assert client.ping() is True
    verbs = [command_verb(payload) for payload in sockets[0].sent]
    assert verbs == ["AUTH", "SELECT", "PING"]
    assert b"2" in sockets[0].sent[1]


def test_auth_rejection_is_sanitized(monkeypatch: Any) -> None:
    patch_connection(
        monkeypatch,
        b"-ERR invalid password " + SENTINEL_PASSWORD.encode() + b"\r\n",
    )
    client = RedisClient(
        RedisEndpoint(
            host="127.0.0.1",
            port=6379,
            timeout_seconds=2.0,
            database=0,
            password=SENTINEL_PASSWORD,
        )
    )

    with pytest.raises(RedisAuthenticationError) as error:
        client.ping()
    assert str(error.value) == "Redis authentication failed"
    assert error.value.__cause__ is None
    assert_no_secret(str(error.value))
    assert_no_secret(repr(error.value))


def test_auth_connection_close_is_not_authentication_failure(
    monkeypatch: Any,
) -> None:
    patch_connection(monkeypatch, b"")
    client = RedisClient(
        RedisEndpoint(
            host="127.0.0.1",
            port=6379,
            timeout_seconds=2.0,
            database=0,
            password=SENTINEL_PASSWORD,
        )
    )

    with pytest.raises(RedisConnectionError, match="connection closed"):
        client.ping()


def test_select_failure_is_not_authentication_failure(monkeypatch: Any) -> None:
    patch_connection(monkeypatch, b"+OK\r\n-ERR invalid DB index\r\n")
    client = _auth_client()

    with pytest.raises(RedisCommandError, match="invalid DB index") as error:
        client.ping()
    assert not isinstance(error.value, RedisAuthenticationError)


def _auth_client() -> RedisClient:
    return RedisClient(
        RedisEndpoint(
            host="127.0.0.1",
            port=6379,
            timeout_seconds=2.0,
            database=0,
            password=SENTINEL_PASSWORD,
        )
    )


def test_auth_unknown_prefix_is_protocol_error(monkeypatch: Any) -> None:
    patch_connection(monkeypatch, b"?oops\r\n")
    with pytest.raises(RedisProtocolError) as error:
        _auth_client().ping()
    assert type(error.value) is RedisProtocolError
    assert str(error.value) == "unknown RESP prefix"
    assert_no_secret(str(error.value))


def test_auth_invalid_utf8_is_protocol_error_without_raw_bytes(
    monkeypatch: Any,
) -> None:
    patch_connection(monkeypatch, b"+\xff\r\n")
    with pytest.raises(RedisProtocolError) as error:
        _auth_client().ping()
    assert type(error.value) is RedisProtocolError
    assert str(error.value) == "Redis response is not valid UTF-8"
    assert_no_secret(str(error.value))


def test_auth_non_ok_success_shapes_are_protocol_errors(monkeypatch: Any) -> None:
    for payload in (b"+PONG\r\n", b":1\r\n", b"$2\r\nOK\r\n"):
        patch_connection(monkeypatch, payload)
        with pytest.raises(RedisProtocolError) as error:
            _auth_client().ping()
        assert type(error.value) is RedisProtocolError
        assert str(error.value) == "unexpected AUTH response"
        assert_no_secret(str(error.value))


def test_select_non_ok_success_shapes_are_protocol_errors(monkeypatch: Any) -> None:
    for payload in (
        b"+OK\r\n+PONG\r\n",
        b"+OK\r\n:1\r\n",
        b"+OK\r\n$2\r\nOK\r\n",
    ):
        patch_connection(monkeypatch, payload)
        with pytest.raises(RedisProtocolError) as error:
            _auth_client().ping()
        assert type(error.value) is RedisProtocolError
        assert str(error.value) == "unexpected SELECT response"
        assert_no_secret(str(error.value))


def test_endpoint_equality_includes_password_without_leaking_it() -> None:
    left = RedisEndpoint(
        host="127.0.0.1",
        port=6379,
        timeout_seconds=2.0,
        database=0,
        password=SENTINEL_PASSWORD,
    )
    same = RedisEndpoint(
        host="127.0.0.1",
        port=6379,
        timeout_seconds=2.0,
        database=0,
        password=SENTINEL_PASSWORD,
    )
    other = RedisEndpoint(
        host="127.0.0.1",
        port=6379,
        timeout_seconds=2.0,
        database=0,
        password="other-password",
    )
    if left != same:
        raise AssertionError("equal passwords did not compare equal")
    if left == other:
        raise AssertionError("different passwords compared equal")
    if hash(left) == hash(other):
        raise AssertionError("different passwords hashed equal")
    assert_no_secret(repr(left))
    from dataclasses import asdict

    assert_no_secret(str(asdict(left)))
    assert_no_secret(str(asdict(other)))
