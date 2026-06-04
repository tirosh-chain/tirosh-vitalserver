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
            raise RedisProtocolError(
                f"unexpected SMEMBERS response for {key}: {value!r}"
            )
        for item in value:
            if not isinstance(item, str):
                raise RedisProtocolError(
                    f"unexpected SMEMBERS member for {key}: {item!r}"
                )
        return sorted(value)

    def lrange(self, key: str, start: int, stop: int) -> list[str]:
        value = self.command("LRANGE", key, str(start), str(stop))
        if not isinstance(value, list):
            raise RedisProtocolError(f"unexpected LRANGE response for {key}: {value!r}")
        for item in value:
            if not isinstance(item, str):
                raise RedisProtocolError(
                    f"unexpected LRANGE item for {key}: {item!r}"
                )
        return value

    def scan(self, pattern: str, count: int = 1000) -> list[str]:
        cursor = "0"
        seen_cursors: set[str] = set()
        keys: set[str] = set()
        while cursor not in seen_cursors:
            seen_cursors.add(cursor)
            value = self.command("SCAN", cursor, "MATCH", pattern, "COUNT", str(count))
            if not isinstance(value, list) or len(value) != 2:
                raise RedisProtocolError(
                    f"unexpected SCAN response for {pattern}: {value!r}"
                )
            next_cursor, page = value
            if not isinstance(next_cursor, str | int):
                raise RedisProtocolError(
                    f"unexpected SCAN cursor for {pattern}: {next_cursor!r}"
                )
            if not isinstance(page, list):
                raise RedisProtocolError(
                    f"unexpected SCAN page for {pattern}: {page!r}"
                )
            for item in page:
                if not isinstance(item, str):
                    raise RedisProtocolError(
                        f"unexpected SCAN key for {pattern}: {item!r}"
                    )
                keys.add(item)
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
