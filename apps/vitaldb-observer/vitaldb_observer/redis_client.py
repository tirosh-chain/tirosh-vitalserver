from __future__ import annotations

import socket
from dataclasses import dataclass
from typing import Any


class RedisProtocolError(RuntimeError):
    pass


@dataclass(frozen=True)
class RedisEndpoint:
    host: str
    port: int
    timeout_seconds: float


class RedisClient:
    def __init__(self, endpoint: RedisEndpoint) -> None:
        self._endpoint = endpoint

    def ping(self) -> bool:
        return self.command("PING") == "PONG"

    def get(self, key: str) -> str | None:
        value = self.command("GET", key)
        if value is None:
            return None
        if isinstance(value, str):
            return value
        raise RedisProtocolError(f"unexpected GET response for {key}: {value!r}")

    def smembers(self, key: str) -> list[str]:
        value = self.command("SMEMBERS", key)
        if not isinstance(value, list):
            return []
        return sorted(item for item in value if isinstance(item, str))

    def scan(self, pattern: str, count: int = 1000) -> list[str]:
        cursor = "0"
        seen_cursors: set[str] = set()
        keys: set[str] = set()
        while cursor not in seen_cursors:
            seen_cursors.add(cursor)
            value = self.command("SCAN", cursor, "MATCH", pattern, "COUNT", str(count))
            if not isinstance(value, list) or len(value) != 2:
                return sorted(keys)
            next_cursor, page = value
            if isinstance(page, list):
                keys.update(item for item in page if isinstance(item, str))
            cursor = str(next_cursor)
            if cursor == "0":
                break
        return sorted(keys)

    def command(self, *parts: str) -> Any:
        with socket.create_connection(
            (self._endpoint.host, self._endpoint.port),
            timeout=self._endpoint.timeout_seconds,
        ) as connection:
            connection.settimeout(self._endpoint.timeout_seconds)
            connection.sendall(_encode_command(parts))
            return _RESPReader(connection).read()


class _RESPReader:
    def __init__(self, connection: socket.socket) -> None:
        self._connection = connection

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
            return data.decode()
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


def _encode_command(parts: tuple[str, ...]) -> bytes:
    encoded = [f"*{len(parts)}\r\n".encode()]
    for part in parts:
        raw = part.encode()
        encoded.append(f"${len(raw)}\r\n".encode())
        encoded.append(raw)
        encoded.append(b"\r\n")
    return b"".join(encoded)
