from __future__ import annotations

import socket
import ssl
import time
from collections.abc import Callable, Iterable
from datetime import UTC, datetime
from types import TracebackType
from typing import Any

from .replication import (
    KeyType,
    RedisKeySnapshot,
    TargetPublishResult,
    TargetPublishStatus,
    fingerprint,
)
from .settings import (
    RedisEndpoint,
    RelayPublishContract,
    default_publish_contract,
)

PUBLISH_SNAPSHOT_SCRIPT = """
local target_key = KEYS[1]
local event_stream_key = KEYS[2]
local fingerprint_hash_key = KEYS[3]
local publish_dedupe_hash_key = KEYS[4]

local source_key = ARGV[1]
local key_type = ARGV[2]
local ttl_ms = ARGV[3]
local payload = ARGV[4]
local source_fingerprint = ARGV[5]
local dedupe_key = ARGV[6]
local published_at = ARGV[7]
local publisher_id = ARGV[8]
local maxlen = ARGV[9]

local current_fingerprint = redis.call('HGET', fingerprint_hash_key, target_key)
local target_exists = redis.call('EXISTS', target_key)
if current_fingerprint == source_fingerprint and target_exists == 1 then
  return {'unchanged', target_key, ''}
end

local existing_event_id = redis.call('HGET', publish_dedupe_hash_key, dedupe_key)
if existing_event_id then
  return {'duplicate', target_key, existing_event_id}
end

redis.call('RESTORE', target_key, ttl_ms, payload, 'REPLACE')
local event_id
if maxlen ~= '' then
  event_id = redis.call(
    'XADD',
    event_stream_key,
    'MAXLEN',
    '~',
    maxlen,
    '*',
    'schema_version',
    '1',
    'event',
    'key_published',
    'source_key',
    source_key,
    'target_key',
    target_key,
    'key_type',
    key_type,
    'ttl_ms',
    ttl_ms,
    'source_fingerprint',
    source_fingerprint,
    'dedupe_key',
    dedupe_key,
    'published_at',
    published_at,
    'publisher',
    publisher_id
  )
else
  event_id = redis.call(
    'XADD',
    event_stream_key,
    '*',
    'schema_version',
    '1',
    'event',
    'key_published',
    'source_key',
    source_key,
    'target_key',
    target_key,
    'key_type',
    key_type,
    'ttl_ms',
    ttl_ms,
    'source_fingerprint',
    source_fingerprint,
    'dedupe_key',
    dedupe_key,
    'published_at',
    published_at,
    'publisher',
    publisher_id
  )
end
redis.call('HSET', fingerprint_hash_key, target_key, source_fingerprint)
redis.call('HSET', publish_dedupe_hash_key, dedupe_key, event_id)
return {'published', target_key, event_id}
""".strip()


class RedisProtocolError(RuntimeError):
    pass


class RedisConnectionError(RedisProtocolError):
    pass


class RedisAuthenticationError(RedisProtocolError):
    pass


class RedisClient:
    def __init__(
        self,
        endpoint: RedisEndpoint,
        *,
        publish_contract: RelayPublishContract | None = None,
        timeout_seconds: float = 2.0,
        retry_attempts: int = 2,
        retry_initial_backoff_seconds: float = 0.25,
        retry_max_backoff_seconds: float = 2.0,
        retry_sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self._endpoint = endpoint
        self._publish_contract = publish_contract or default_publish_contract()
        self._timeout_seconds = timeout_seconds
        self._retry_attempts = retry_attempts
        self._retry_initial_backoff_seconds = retry_initial_backoff_seconds
        self._retry_max_backoff_seconds = retry_max_backoff_seconds
        self._retry_sleep = retry_sleep

    def scan_keys(self, *, count: int) -> list[str]:
        with self.session() as session:
            return session.scan_keys(count=count)

    def dump_key(self, key: str) -> RedisKeySnapshot | None:
        with self.session() as session:
            return session.dump_key(key)

    def publish_snapshot_if_changed(
        self,
        snapshot: RedisKeySnapshot,
    ) -> TargetPublishResult:
        with self.session() as session:
            return session.publish_snapshot_if_changed(snapshot)

    def command(self, *parts: str) -> Any:
        with self.session() as session:
            return session.command(*parts)

    def raw_command(self, *parts: str) -> Any:
        with self.session() as session:
            return session.raw_command(*parts)

    def command_bytes(self, parts: Iterable[str | bytes]) -> Any:
        with self.session() as session:
            return session.command_bytes(parts)

    def session(self) -> RedisClientSession:
        return RedisClientSession(
            self._endpoint,
            publish_contract=self._publish_contract,
            timeout_seconds=self._timeout_seconds,
            retry_attempts=self._retry_attempts,
            retry_initial_backoff_seconds=self._retry_initial_backoff_seconds,
            retry_max_backoff_seconds=self._retry_max_backoff_seconds,
            retry_sleep=self._retry_sleep,
        )


class RedisClientSession:
    def __init__(
        self,
        endpoint: RedisEndpoint,
        *,
        publish_contract: RelayPublishContract,
        timeout_seconds: float,
        retry_attempts: int,
        retry_initial_backoff_seconds: float,
        retry_max_backoff_seconds: float,
        retry_sleep: Callable[[float], None],
    ) -> None:
        self._endpoint = endpoint
        self._publish_contract = publish_contract
        self._timeout_seconds = timeout_seconds
        self._retry_attempts = retry_attempts
        self._retry_initial_backoff_seconds = retry_initial_backoff_seconds
        self._retry_max_backoff_seconds = retry_max_backoff_seconds
        self._retry_sleep = retry_sleep
        self._connection: socket.socket | ssl.SSLSocket | None = None

    def __enter__(self) -> RedisClientSession:
        self._connection = self._connect_with_retry()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        if self._connection is not None:
            self._connection.close()
            self._connection = None

    def scan_keys(self, *, count: int) -> list[str]:
        cursor = "0"
        keys: list[str] = []
        seen: set[str] = set()
        while cursor not in seen:
            seen.add(cursor)
            value = self.command("SCAN", cursor, "COUNT", str(count))
            if not isinstance(value, list) or len(value) != 2:
                raise RedisProtocolError(f"unexpected SCAN response: {value!r}")
            next_cursor, page = value
            if not isinstance(next_cursor, str | int) or not isinstance(page, list):
                raise RedisProtocolError(f"unexpected SCAN page: {value!r}")
            for item in page:
                keys.append(_decode_text(item))
            cursor = str(next_cursor)
            if cursor == "0":
                break
        return sorted(set(keys))

    def dump_key(self, key: str) -> RedisKeySnapshot | None:
        key_type = _key_type(self.command("TYPE", key))
        if key_type == KeyType.NONE:
            return None
        ttl_ms = self.command("PTTL", key)
        if not isinstance(ttl_ms, int):
            raise RedisProtocolError(f"unexpected PTTL response for {key}: {ttl_ms!r}")
        payload = self.raw_command("DUMP", key)
        if payload is None:
            return None
        if not isinstance(payload, bytes):
            raise RedisProtocolError(f"unexpected DUMP response for {key}: {payload!r}")
        return RedisKeySnapshot(
            key=key,
            key_type=key_type,
            ttl_ms=ttl_ms,
            serialized_payload=payload,
        )

    def publish_snapshot_if_changed(
        self,
        snapshot: RedisKeySnapshot,
    ) -> TargetPublishResult:
        contract = self._publish_contract
        target_key = f"{contract.target_key_prefix}{snapshot.key}"
        ttl_ms = str(snapshot.ttl_ms if snapshot.ttl_ms > 0 else 0)
        source_fingerprint = fingerprint(snapshot.serialized_payload)
        dedupe_key = fingerprint(
            "\0".join(
                (
                    "vitalserver-redis-relay-v1",
                    snapshot.key,
                    target_key,
                    source_fingerprint,
                )
            ).encode("utf-8")
        )
        maxlen = (
            str(contract.event_stream_maxlen)
            if contract.event_stream_maxlen is not None
            else ""
        )
        response = self.command_bytes(
            [
                "EVAL",
                PUBLISH_SNAPSHOT_SCRIPT,
                "4",
                target_key,
                contract.event_stream_key,
                contract.fingerprint_hash_key,
                contract.publish_dedupe_hash_key,
                snapshot.key,
                snapshot.key_type.value,
                ttl_ms,
                snapshot.serialized_payload,
                source_fingerprint,
                dedupe_key,
                _utc_timestamp(),
                contract.publisher_id,
                maxlen,
            ]
        )
        if not isinstance(response, list) or len(response) != 3:
            raise RedisProtocolError(f"unexpected publish response: {response!r}")
        status = _publish_status(response[0])
        return TargetPublishResult(
            source_key=snapshot.key,
            target_key=_decode_text(response[1]),
            status=status,
            event_id=_event_id(response[2]),
        )

    def command(self, *parts: str) -> Any:
        return self._command(parts, decode_bulk_strings=True)

    def raw_command(self, *parts: str) -> Any:
        return self._command(parts, decode_bulk_strings=False)

    def command_bytes(self, parts: Iterable[str | bytes]) -> Any:
        return self._command(tuple(parts), decode_bulk_strings=True)

    def _command(
        self,
        parts: tuple[str | bytes, ...],
        *,
        decode_bulk_strings: bool,
    ) -> Any:
        encoded = _encode_command(parts)
        last_error: BaseException | None = None
        for attempt in range(self._retry_attempts + 1):
            try:
                connection = self._active_connection()
                connection.sendall(encoded)
                return _RESPReader(
                    connection,
                    decode_bulk_strings=decode_bulk_strings,
                ).read()
            except _RETRYABLE_CONNECTION_ERRORS as error:
                last_error = error
                self._close_connection()
                if attempt >= self._retry_attempts:
                    raise RedisConnectionError(
                        "Redis command failed after reconnect attempts: "
                        f"{error}"
                    ) from error
                self._sleep_before_retry(attempt)
                self._connection = self._connect_with_retry()
        raise RedisConnectionError(
            "Redis command failed without a response"
        ) from last_error

    def _connect(self) -> socket.socket | ssl.SSLSocket:
        raw = socket.create_connection(
            (self._endpoint.host, self._endpoint.port),
            timeout=self._timeout_seconds,
        )
        raw.settimeout(self._timeout_seconds)
        connection: socket.socket | ssl.SSLSocket = raw
        if self._endpoint.tls:
            context = ssl.create_default_context()
            connection = context.wrap_socket(
                raw,
                server_hostname=self._endpoint.host,
            )
        self._authenticate(connection)
        if self._endpoint.database:
            connection.sendall(
                _encode_command(("SELECT", str(self._endpoint.database)))
            )
            _RESPReader(connection, decode_bulk_strings=True).read()
        return connection

    def _connect_with_retry(self) -> socket.socket | ssl.SSLSocket:
        last_error: BaseException | None = None
        for attempt in range(self._retry_attempts + 1):
            try:
                return self._connect()
            except _RETRYABLE_CONNECTION_ERRORS as error:
                last_error = error
                if attempt >= self._retry_attempts:
                    raise RedisConnectionError(
                        "Redis connection failed after reconnect attempts: "
                        f"{error}"
                    ) from error
                self._sleep_before_retry(attempt)
        raise RedisConnectionError(
            "Redis connection failed without a response"
        ) from last_error

    def _sleep_before_retry(self, attempt: int) -> None:
        delay = min(
            self._retry_initial_backoff_seconds * (2**attempt),
            self._retry_max_backoff_seconds,
        )
        if delay > 0:
            self._retry_sleep(delay)

    def _close_connection(self) -> None:
        if self._connection is not None:
            self._connection.close()
            self._connection = None

    def _active_connection(self) -> socket.socket | ssl.SSLSocket:
        if self._connection is None:
            raise RedisProtocolError("Redis session is not open")
        return self._connection

    def _authenticate(self, connection: socket.socket | ssl.SSLSocket) -> None:
        if not self._endpoint.password:
            return
        parts: tuple[str, ...]
        if self._endpoint.username:
            parts = ("AUTH", self._endpoint.username, self._endpoint.password)
        else:
            parts = ("AUTH", self._endpoint.password)
        connection.sendall(_encode_command(parts))
        try:
            _RESPReader(connection, decode_bulk_strings=True).read()
        except RedisConnectionError:
            raise
        except RedisProtocolError:
            raise RedisAuthenticationError("Redis authentication failed") from None


class _RESPReader:
    def __init__(
        self,
        connection: socket.socket | ssl.SSLSocket,
        *,
        decode_bulk_strings: bool,
    ) -> None:
        self._connection = connection
        self._decode_bulk_strings = decode_bulk_strings

    def read(self) -> Any:
        prefix = self._read_exact(1)
        if prefix == b"+":
            return self._read_line().decode()
        if prefix == b"-":
            raise RedisProtocolError(self._read_line().decode())
        if prefix == b":":
            return int(self._read_line().decode())
        if prefix == b"$":
            length = int(self._read_line().decode())
            if length == -1:
                return None
            data = self._read_exact(length)
            self._read_exact(2)
            return data.decode() if self._decode_bulk_strings else data
        if prefix == b"*":
            length = int(self._read_line().decode())
            if length == -1:
                return None
            return [self.read() for _ in range(length)]
        raise RedisProtocolError(f"unknown RESP prefix: {prefix!r}")

    def _read_line(self) -> bytes:
        chunks: list[bytes] = []
        while True:
            chunk = self._read_exact(1)
            if chunk == b"\r":
                self._read_exact(1)
                return b"".join(chunks)
            chunks.append(chunk)

    def _read_exact(self, length: int) -> bytes:
        data = b""
        while len(data) < length:
            chunk = self._connection.recv(length - len(data))
            if not chunk:
                raise RedisConnectionError(
                    "connection closed while reading Redis response"
                )
            data += chunk
        return data


_RETRYABLE_CONNECTION_ERRORS = (
    OSError,
    TimeoutError,
    RedisConnectionError,
)


def _encode_command(parts: tuple[str | bytes, ...]) -> bytes:
    encoded = [f"*{len(parts)}\r\n".encode()]
    for part in parts:
        raw = part if isinstance(part, bytes) else part.encode()
        encoded.append(f"${len(raw)}\r\n".encode())
        encoded.append(raw)
        encoded.append(b"\r\n")
    return b"".join(encoded)


def _decode_text(value: Any) -> str:
    if isinstance(value, bytes):
        return value.decode()
    if isinstance(value, str):
        return value
    raise RedisProtocolError(f"unexpected text value: {value!r}")


def _key_type(value: Any) -> KeyType:
    raw = _decode_text(value)
    try:
        return KeyType(raw)
    except ValueError:
        return KeyType.UNKNOWN


def _publish_status(value: Any) -> TargetPublishStatus:
    raw = _decode_text(value)
    try:
        return TargetPublishStatus(raw)
    except ValueError as error:
        raise RedisProtocolError(f"unexpected publish status: {raw!r}") from error


def _event_id(value: Any) -> str | None:
    raw = _decode_text(value)
    return raw or None


def _utc_timestamp() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")
