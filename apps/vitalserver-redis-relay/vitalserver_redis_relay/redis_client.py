from __future__ import annotations

import socket
import ssl
from collections.abc import Iterable
from typing import Any

from .replication import KeyType, RedisKeySnapshot, TargetRestoreResult, fingerprint
from .settings import RedisEndpoint


class RedisProtocolError(RuntimeError):
    pass


class RedisClient:
    def __init__(
        self,
        endpoint: RedisEndpoint,
        *,
        timeout_seconds: float = 2.0,
    ) -> None:
        self._endpoint = endpoint
        self._timeout_seconds = timeout_seconds

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

    def restore_key(
        self,
        snapshot: RedisKeySnapshot,
        *,
        replace: bool,
        target_key_prefix: str = "vitalserver:",
        fingerprint_key: str = "tirosh:relay:fingerprints",
    ) -> TargetRestoreResult:
        target_key = f"{target_key_prefix}{snapshot.key}"
        current = self.raw_command("HGET", fingerprint_key, target_key)
        expected = fingerprint(snapshot.serialized_payload).encode("ascii")
        exists = self.command("EXISTS", target_key)
        if current == expected and exists == 1:
            return TargetRestoreResult(
                source_key=snapshot.key,
                target_key=target_key,
                changed=False,
            )
        ttl_ms = str(snapshot.ttl_ms if snapshot.ttl_ms > 0 else 0)
        parts: list[str | bytes] = [
            "RESTORE",
            target_key,
            ttl_ms,
            snapshot.serialized_payload,
        ]
        if replace:
            parts.append("REPLACE")
        self.command_bytes(parts)
        self.command_bytes(["HSET", fingerprint_key, target_key, expected])
        return TargetRestoreResult(
            source_key=snapshot.key,
            target_key=target_key,
            changed=True,
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
        with socket.create_connection(
            (self._endpoint.host, self._endpoint.port),
            timeout=self._timeout_seconds,
        ) as raw:
            raw.settimeout(self._timeout_seconds)
            connection: socket.socket | ssl.SSLSocket = raw
            if self._endpoint.tls:
                context = ssl.create_default_context()
                connection = context.wrap_socket(
                    raw,
                    server_hostname=self._endpoint.host,
                )
            try:
                self._authenticate(connection)
                if self._endpoint.database:
                    connection.sendall(
                        _encode_command(("SELECT", str(self._endpoint.database)))
                    )
                    _RESPReader(connection, decode_bulk_strings=True).read()
                connection.sendall(_encode_command(parts))
                return _RESPReader(
                    connection,
                    decode_bulk_strings=decode_bulk_strings,
                ).read()
            finally:
                connection.close()

    def _authenticate(self, connection: socket.socket | ssl.SSLSocket) -> None:
        if not self._endpoint.password:
            return
        if self._endpoint.username:
            parts = ("AUTH", self._endpoint.username, self._endpoint.password)
        else:
            parts = ("AUTH", self._endpoint.password)
        connection.sendall(_encode_command(parts))
        _RESPReader(connection, decode_bulk_strings=True).read()


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
                raise RedisProtocolError(
                    "connection closed while reading Redis response"
                )
            data += chunk
        return data


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
