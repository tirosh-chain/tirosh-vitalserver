from __future__ import annotations

import socket
from dataclasses import dataclass
from typing import Any, cast


class RedisProtocolError(RuntimeError):
    pass


class RedisConnectionError(RedisProtocolError):
    pass


class RedisAuthenticationError(RedisProtocolError):
    pass


class RedisCommandError(RedisProtocolError):
    pass


@dataclass(frozen=True, init=False, eq=False)
class RedisEndpoint:
    host: str
    port: int
    timeout_seconds: float
    database: int = 0

    def __init__(
        self,
        host: str,
        port: int,
        timeout_seconds: float,
        database: int = 0,
        password: str | None = None,
    ) -> None:
        object.__setattr__(self, "host", host)
        object.__setattr__(self, "port", port)
        object.__setattr__(self, "timeout_seconds", timeout_seconds)
        object.__setattr__(self, "database", database)
        # Keep password off dataclass fields so asdict/repr cannot leak it.
        object.__setattr__(self, "_password", password)

    @property
    def password(self) -> str | None:
        return cast(str | None, object.__getattribute__(self, "_password"))

    @property
    def password_configured(self) -> bool:
        return self.password is not None

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, RedisEndpoint):
            return NotImplemented
        return (
            self.host,
            self.port,
            self.timeout_seconds,
            self.database,
            self.password,
        ) == (
            other.host,
            other.port,
            other.timeout_seconds,
            other.database,
            other.password,
        )

    def __hash__(self) -> int:
        return hash(
            (
                self.host,
                self.port,
                self.timeout_seconds,
                self.database,
                self.password,
            )
        )

    def __repr__(self) -> str:
        return (
            "RedisEndpoint("
            f"host={self.host!r}, "
            f"port={self.port}, "
            f"timeout_seconds={self.timeout_seconds}, "
            f"database={self.database}, "
            f"password_configured={self.password_configured})"
        )


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
                raise RedisProtocolError(f"unexpected LRANGE item for {key}: {item!r}")
        return value

    def scan(self, pattern: str, count: int = 1000) -> list[str]:
        cursor = "0"
        seen_cursors: set[str] = set()
        keys: set[str] = set()
        while cursor not in seen_cursors:
            seen_cursors.add(cursor)
            next_cursor, page = self.scan_page(
                cursor=cursor,
                pattern=pattern,
                count=count,
            )
            keys.update(page)
            cursor = str(next_cursor)
            if cursor == "0":
                break
        return sorted(keys)

    def scan_page(
        self,
        *,
        cursor: str,
        pattern: str = "*",
        count: int = 1000,
    ) -> tuple[str, list[str]]:
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
            raise RedisProtocolError(f"unexpected SCAN page for {pattern}: {page!r}")
        keys: list[str] = []
        for item in page:
            if not isinstance(item, str):
                raise RedisProtocolError(f"unexpected SCAN key for {pattern}: {item!r}")
            keys.append(item)
        return str(next_cursor), sorted(keys)

    def command(self, *parts: str) -> Any:
        return self._command(parts, decode_bulk_strings=True)

    def _command(self, parts: tuple[str, ...], *, decode_bulk_strings: bool) -> Any:
        with socket.create_connection(
            (self._endpoint.host, self._endpoint.port),
            timeout=self._endpoint.timeout_seconds,
        ) as connection:
            connection.settimeout(self._endpoint.timeout_seconds)
            self._prepare_connection(connection)
            connection.sendall(_encode_command(parts))
            return _RESPReader(
                connection,
                decode_bulk_strings=decode_bulk_strings,
            ).read()

    def _prepare_connection(self, connection: socket.socket) -> None:
        password = self._endpoint.password
        if password is not None:
            connection.sendall(_encode_command(("AUTH", password)))
            try:
                _read_simple_ok(connection, action="AUTH")
            except RedisConnectionError:
                raise
            except RedisCommandError:
                raise RedisAuthenticationError("Redis authentication failed") from None
        connection.sendall(_encode_command(("SELECT", str(self._endpoint.database))))
        _read_simple_ok(connection, action="SELECT")


class _RESPReader:
    def __init__(self, connection: socket.socket, *, decode_bulk_strings: bool) -> None:
        self._connection = connection
        self._decode_bulk_strings = decode_bulk_strings

    def read(self) -> Any:
        prefix = self._read_exact(1)
        if prefix == b"+":
            return _decode_resp_text(self._read_line())
        if prefix == b"-":
            raise RedisCommandError(_decode_resp_text(self._read_line()))
        if prefix == b":":
            return _decode_resp_int(self._read_line())
        if prefix == b"$":
            length = _decode_resp_int(self._read_line())
            if length == -1:
                return None
            data = self._read_exact(length)
            self._read_exact(2)
            return _decode_resp_text(data) if self._decode_bulk_strings else data
        if prefix == b"*":
            length = _decode_resp_int(self._read_line())
            if length == -1:
                return None
            return [self.read() for _ in range(length)]
        raise RedisProtocolError("unknown RESP prefix")

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


def _read_simple_ok(connection: socket.socket, *, action: str) -> None:
    reader = _RESPReader(connection, decode_bulk_strings=True)
    prefix = reader._read_exact(1)
    if prefix == b"-":
        raise RedisCommandError(_decode_resp_text(reader._read_line()))
    if prefix == b"+":
        value = _decode_resp_text(reader._read_line())
        if value != "OK":
            raise RedisProtocolError(f"unexpected {action} response")
        return
    if prefix in {b":", b"$", b"*"}:
        raise RedisProtocolError(f"unexpected {action} response")
    raise RedisProtocolError("unknown RESP prefix")


def _decode_resp_text(data: bytes) -> str:
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise RedisProtocolError("Redis response is not valid UTF-8") from None


def _decode_resp_int(data: bytes) -> int:
    try:
        return int(_decode_resp_text(data))
    except ValueError:
        raise RedisProtocolError("Redis response is invalid") from None


def _encode_command(parts: tuple[str, ...]) -> bytes:
    encoded = [f"*{len(parts)}\r\n".encode()]
    for part in parts:
        raw = part.encode()
        encoded.append(f"${len(raw)}\r\n".encode())
        encoded.append(raw)
        encoded.append(b"\r\n")
    return b"".join(encoded)
