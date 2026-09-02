from __future__ import annotations

import io
import json
from pathlib import Path
from typing import Any

import pytest

from vitaldb_observer.collector import VitalDBCollector
from vitaldb_observer.config import ObserverSettings
from vitaldb_observer.redis_client import (
    RedisAuthenticationError,
    RedisEndpoint,
    RedisProtocolError,
)
from vitaldb_observer.server import ObserverRequestHandler, main

SENTINEL_PASSWORD = "observer-sentinel-password-not-for-logs"


def assert_no_secret(payload: str) -> None:
    if SENTINEL_PASSWORD in payload:
        raise AssertionError("secret value leaked")


class FakeRedis:
    def __init__(
        self, *, ping_result: bool = True, error: Exception | None = None
    ) -> None:
        self.ping_result = ping_result
        self.error = error

    def ping(self) -> bool:
        if self.error is not None:
            raise self.error
        return self.ping_result

    def get(self, key: str) -> str | None:
        if self.error is not None:
            raise self.error
        del key
        return None

    def smembers(self, key: str) -> list[str]:
        if self.error is not None:
            raise self.error
        del key
        return []

    def lrange(self, key: str, start: int, stop: int) -> list[str]:
        if self.error is not None:
            raise self.error
        del key, start, stop
        return []

    def scan(self, pattern: str) -> list[str]:
        if self.error is not None:
            raise self.error
        del pattern
        return []


class _FakeSocket:
    def __init__(self, request_bytes: bytes) -> None:
        self._incoming = io.BytesIO(request_bytes)
        self._outgoing = io.BytesIO()

    def makefile(self, mode: str, buffering: int = -1) -> io.BytesIO:
        del buffering
        if "w" in mode:
            return self._outgoing
        return self._incoming

    def sendall(self, data: bytes) -> None:
        self._outgoing.write(data)


class _HandlerServer:
    def __init__(self, settings: ObserverSettings, redis: FakeRedis) -> None:
        self.settings = settings
        self.collector = VitalDBCollector(redis_client=redis, settings=settings)


def _settings(access_log: Path | None = None) -> ObserverSettings:
    return ObserverSettings(
        host="127.0.0.1",
        port=0,
        redis_host="redis",
        redis_port=6379,
        redis_timeout_seconds=1,
        recorder_online_threshold_seconds=120,
        recorder_activity_window_seconds=300,
        audit_redis_list="vitalserver:audit_events",
        audit_event_limit=1000,
        access_log_path=str(access_log) if access_log else "",
        access_log_limit=20,
        redis_endpoint=RedisEndpoint(
            host="redis",
            port=6379,
            timeout_seconds=1,
            database=0,
        ),
    )


def _handle_get(
    path: str, settings: ObserverSettings, redis: FakeRedis
) -> tuple[int, dict[str, str], dict[str, Any]]:
    request: Any = _FakeSocket(f"GET {path} HTTP/1.1\r\nHost: test\r\n\r\n".encode())
    server: Any = _HandlerServer(settings, redis)
    ObserverRequestHandler(request, ("127.0.0.1", 0), server)
    raw = request._outgoing.getvalue()
    header_blob, separator, body = raw.partition(b"\r\n\r\n")
    if separator == b"":
        raise AssertionError("handler did not write an HTTP response")
    status_line, _, header_text = header_blob.decode().partition("\r\n")
    parts = status_line.split(" ")
    status = int(parts[1])
    headers: dict[str, str] = {}
    if header_text:
        for line in header_text.split("\r\n"):
            name, value = line.split(":", 1)
            headers[name] = value.strip()
    payload = json.loads(body.decode())
    return status, headers, payload


def test_main_help_lists_password_file_not_password_value(
    capsys: pytest.CaptureFixture[str],
) -> None:
    with pytest.raises(SystemExit) as exit_info:
        main(["--help"])
    assert exit_info.value.code == 0
    output = capsys.readouterr().out
    assert "--redis-password-file" in output
    assert "--host" in output
    assert "--redis-database" in output
    assert "--redis-password " not in output


def test_main_invalid_settings_exit_without_traceback(
    capsys: pytest.CaptureFixture[str],
) -> None:
    with pytest.raises(SystemExit) as exit_info:
        main(["--port", "0"])
    assert exit_info.value.code == 2
    captured = capsys.readouterr()
    assert "port must be >= 1" in captured.err
    assert captured.err.count("Traceback") == 0


def test_health_is_alive_when_redis_fails() -> None:
    status, headers, payload = _handle_get(
        "/health",
        _settings(),
        FakeRedis(error=RedisProtocolError("redis down")),
    )
    assert status == 200
    assert headers["Content-Type"] == "application/json"
    assert payload["status"] == "ok"
    assert "observedAt" in payload


def test_ready_succeeds_after_redis_ping() -> None:
    status, headers, payload = _handle_get("/ready", _settings(), FakeRedis())
    assert status == 200
    assert headers["Content-Type"] == "application/json"
    assert payload["ready"] is True


def test_ready_auth_failure_is_sanitized() -> None:
    error = RedisAuthenticationError("Redis authentication failed")
    status, headers, payload = _handle_get(
        "/ready",
        _settings(),
        FakeRedis(error=error),
    )
    assert status == 503
    assert headers["Content-Type"] == "application/json"
    assert payload["ready"] is False
    assert payload["error"] == "Redis authentication failed"
    assert_no_secret(json.dumps(payload))


def test_observations_keep_snapshot_when_access_log_is_missing(
    tmp_path: Path,
) -> None:
    status, headers, payload = _handle_get(
        "/api/v1/observations",
        _settings(tmp_path / "missing-access.jsonl"),
        FakeRedis(),
    )
    assert status == 200
    assert headers["Content-Type"] == "application/json"
    assert payload["ready"] is True
    assert payload["proxyConnections"] == []
    assert payload["readIssues"][0]["source"] == "proxyAccessLog"


def test_observations_redis_failure_keeps_unhealthy_shape(
    capsys: pytest.CaptureFixture[str],
) -> None:
    error = RedisAuthenticationError("Redis authentication failed")
    status, headers, payload = _handle_get(
        "/api/v1/observations",
        _settings(),
        FakeRedis(error=error),
    )
    assert status == 503
    assert headers["Content-Type"] == "application/json"
    assert payload["ready"] is False
    assert payload["recorders"] == []
    assert payload["anomalies"][0]["kind"] == "observer-unhealthy"
    assert payload["anomalies"][0]["message"] == "Redis authentication failed"
    assert_no_secret(json.dumps(payload))
    assert_no_secret(capsys.readouterr().out)
