from __future__ import annotations

import os
from dataclasses import asdict
from pathlib import Path

import pytest

from vitaldb_observer.config import ObserverSettingsError, load_settings

SENTINEL_PASSWORD = "observer-sentinel-password-not-for-logs"


def assert_no_secret(payload: str) -> None:
    if SENTINEL_PASSWORD in payload:
        raise AssertionError("secret value leaked")


def write_secret(path: Path, content: str | bytes) -> Path:
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content, encoding="utf-8")
    return path


def test_default_audit_event_limit_matches_recorder_ingress_retention() -> None:
    settings = load_settings({})

    assert settings.audit_event_limit == 10_000


def test_explicit_audit_event_limit_is_preserved() -> None:
    settings = load_settings({"VITALDB_OBSERVER_AUDIT_EVENT_LIMIT": "12000"})

    assert settings.audit_event_limit == 12_000


def test_missing_environment_uses_documented_defaults() -> None:
    settings = load_settings({})

    assert settings.host == "127.0.0.1"
    assert settings.port == 8080
    assert settings.redis_host == "redis"
    assert settings.redis_port == 6379
    assert settings.redis_database == 0
    assert settings.redis_timeout_seconds == 2.0
    assert settings.recorder_online_threshold_seconds == 120
    assert settings.recorder_activity_window_seconds == 300
    assert settings.audit_redis_list == "vitalserver:audit_events"
    assert settings.access_log_path == ""
    assert settings.access_log_limit == 200
    assert settings.redis_password_file is None
    endpoint = settings.redis_endpoint
    assert endpoint is not None
    assert endpoint.password is None
    assert endpoint.password_configured is False
    assert endpoint.database == 0


def test_cli_overrides_environment() -> None:
    settings = load_settings(
        {
            "VITALDB_OBSERVER_HOST": "0.0.0.0",
            "VITALDB_OBSERVER_PORT": "8080",
            "VITALDB_OBSERVER_REDIS_HOST": "redis",
            "VITALDB_OBSERVER_REDIS_PORT": "6379",
            "VITALDB_OBSERVER_REDIS_DATABASE": "1",
            "VITALDB_OBSERVER_ACCESS_LOG_PATH": "/env/access.log",
        },
        argv=[
            "--host",
            "127.0.0.1",
            "--port",
            "18084",
            "--redis-host",
            "127.0.0.1",
            "--redis-port",
            "6380",
            "--redis-database",
            "2",
            "--access-log-path",
            "/cli/proxy-nginx.access.log",
        ],
    )

    assert settings.host == "127.0.0.1"
    assert settings.port == 18084
    assert settings.redis_host == "127.0.0.1"
    assert settings.redis_port == 6380
    assert settings.redis_database == 2
    assert settings.access_log_path == "/cli/proxy-nginx.access.log"


def test_empty_environment_values_are_invalid() -> None:
    cases = [
        ("VITALDB_OBSERVER_HOST", "host is empty"),
        ("VITALDB_OBSERVER_PORT", "port is empty"),
        ("VITALDB_OBSERVER_REDIS_HOST", "redis-host is empty"),
        ("VITALDB_OBSERVER_REDIS_PORT", "redis-port is empty"),
        ("VITALDB_OBSERVER_REDIS_DATABASE", "redis-database is empty"),
        ("VITALDB_OBSERVER_REDIS_TIMEOUT_SECONDS", "redis-timeout-seconds is empty"),
        (
            "VITALDB_OBSERVER_RECORDER_ONLINE_THRESHOLD_SECONDS",
            "recorder-online-threshold-seconds is empty",
        ),
        (
            "VITALDB_OBSERVER_RECORDER_ACTIVITY_WINDOW_SECONDS",
            "recorder-activity-window-seconds is empty",
        ),
        ("VITALDB_OBSERVER_AUDIT_REDIS_LIST", "audit-redis-list is empty"),
        ("VITALDB_OBSERVER_AUDIT_EVENT_LIMIT", "audit-event-limit is empty"),
        ("VITALDB_OBSERVER_ACCESS_LOG_PATH", "access-log-path is empty"),
        ("VITALDB_OBSERVER_ACCESS_LOG_LIMIT", "access-log-limit is empty"),
        (
            "VITALDB_OBSERVER_REDIS_PASSWORD_FILE",
            "redis-password-file must not be empty",
        ),
    ]
    for key, message in cases:
        with pytest.raises(ObserverSettingsError, match=message):
            load_settings({key: ""})
        with pytest.raises(ObserverSettingsError, match=message):
            load_settings({key: "   "})


def test_empty_cli_values_are_invalid() -> None:
    with pytest.raises(ObserverSettingsError, match="host is empty"):
        load_settings({}, argv=["--host", ""])
    with pytest.raises(ObserverSettingsError, match="access-log-path is empty"):
        load_settings({}, argv=["--access-log-path", "   "])
    with pytest.raises(
        ObserverSettingsError, match="redis-password-file must not be empty"
    ):
        load_settings({}, argv=["--redis-password-file", ""])


def test_invalid_and_out_of_range_numeric_settings() -> None:
    with pytest.raises(ObserverSettingsError, match="port is invalid"):
        load_settings({"VITALDB_OBSERVER_PORT": "abc"})
    with pytest.raises(ObserverSettingsError, match="port must be >= 1"):
        load_settings({"VITALDB_OBSERVER_PORT": "0"})
    with pytest.raises(ObserverSettingsError, match="port must be <= 65535"):
        load_settings({"VITALDB_OBSERVER_PORT": "65536"})
    with pytest.raises(ObserverSettingsError, match="redis-port must be >= 1"):
        load_settings({}, argv=["--redis-port", "0"])
    with pytest.raises(ObserverSettingsError, match="redis-database is invalid"):
        load_settings({"VITALDB_OBSERVER_REDIS_DATABASE": "1.5"})
    with pytest.raises(ObserverSettingsError, match="redis-database must be >= 0"):
        load_settings({"VITALDB_OBSERVER_REDIS_DATABASE": "-1"})
    with pytest.raises(ObserverSettingsError, match="access-log-limit must be >= 1"):
        load_settings({"VITALDB_OBSERVER_ACCESS_LOG_LIMIT": "0"})
    with pytest.raises(ObserverSettingsError, match="audit-event-limit must be >= 1"):
        load_settings({"VITALDB_OBSERVER_AUDIT_EVENT_LIMIT": "0"})
    with pytest.raises(
        ObserverSettingsError,
        match="recorder-activity-window-seconds must be >= 1",
    ):
        load_settings({"VITALDB_OBSERVER_RECORDER_ACTIVITY_WINDOW_SECONDS": "0"})
    with pytest.raises(ObserverSettingsError, match="redis-timeout-seconds is invalid"):
        load_settings({"VITALDB_OBSERVER_REDIS_TIMEOUT_SECONDS": "fast"})
    with pytest.raises(
        ObserverSettingsError, match="redis-timeout-seconds must be a finite number"
    ):
        load_settings({"VITALDB_OBSERVER_REDIS_TIMEOUT_SECONDS": "inf"})
    with pytest.raises(
        ObserverSettingsError, match="redis-timeout-seconds must be > 0"
    ):
        load_settings({"VITALDB_OBSERVER_REDIS_TIMEOUT_SECONDS": "0"})


def test_password_file_is_read_once_and_strips_one_newline(tmp_path: Path) -> None:
    path = write_secret(tmp_path / "password", f"{SENTINEL_PASSWORD}\n")
    settings = load_settings({"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": str(path)})
    path.unlink()

    assert settings.redis_password_file == str(path)
    endpoint = settings.redis_endpoint
    assert endpoint is not None
    assert endpoint.password_configured is True
    loaded = endpoint.password
    if loaded != SENTINEL_PASSWORD:
        raise AssertionError("password file was not loaded at settings time")
    assert_no_secret(repr(settings))
    assert_no_secret(repr(endpoint))
    assert_no_secret(str(asdict(settings)))
    assert_no_secret(str(asdict(endpoint)))


def test_password_file_crlf_and_internal_newline(tmp_path: Path) -> None:
    crlf = write_secret(tmp_path / "crlf", f"{SENTINEL_PASSWORD}\r\n")
    settings = load_settings({"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": str(crlf)})
    crlf_endpoint = settings.redis_endpoint
    assert crlf_endpoint is not None
    if crlf_endpoint.password != SENTINEL_PASSWORD:
        raise AssertionError("CRLF password file was not loaded")

    multiline = write_secret(tmp_path / "multiline", "line-one\nline-two\n")
    settings = load_settings({"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": str(multiline)})
    multiline_endpoint = settings.redis_endpoint
    assert multiline_endpoint is not None
    if multiline_endpoint.password != "line-one\nline-two":
        raise AssertionError("internal newline was not preserved")


def test_password_file_failures_are_distinct(tmp_path: Path) -> None:
    with pytest.raises(ObserverSettingsError, match="redis-password-file is missing"):
        load_settings(
            {"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": str(tmp_path / "missing")}
        )

    empty = write_secret(tmp_path / "empty", "\n")
    with pytest.raises(ObserverSettingsError, match="redis-password-file is empty"):
        load_settings({"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": str(empty)})

    crlf_only = write_secret(tmp_path / "crlf-only", "\r\n")
    with pytest.raises(ObserverSettingsError, match="redis-password-file is empty"):
        load_settings({"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": str(crlf_only)})

    invalid_utf8 = write_secret(tmp_path / "bad-utf8", b"\xff")
    with pytest.raises(
        ObserverSettingsError, match="redis-password-file is not valid UTF-8"
    ):
        load_settings({"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": str(invalid_utf8)})

    with pytest.raises(ObserverSettingsError, match="redis-password-file is invalid"):
        load_settings({"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": "secret\0path"})


def test_password_file_permission_failure_is_explicit(tmp_path: Path) -> None:
    path = write_secret(tmp_path / "password", f"{SENTINEL_PASSWORD}\n")
    path.chmod(0)
    try:
        if os.access(path, os.R_OK):
            pytest.skip("process can read mode 0 files")
        with pytest.raises(
            ObserverSettingsError, match="redis-password-file read failed"
        ) as error:
            load_settings({"VITALDB_OBSERVER_REDIS_PASSWORD_FILE": str(path)})
        assert_no_secret(str(error.value))
        assert error.value.__cause__ is None
    finally:
        path.chmod(0o600)


def test_password_value_cli_option_is_rejected_without_echoing_secret(
    capsys: pytest.CaptureFixture[str],
) -> None:
    from vitaldb_observer.server import main

    spaced = ["--redis-password", SENTINEL_PASSWORD]
    equals = ["--redis-password=" + SENTINEL_PASSWORD]
    for argv in (spaced, equals):
        with pytest.raises(ObserverSettingsError) as error:
            load_settings({}, argv=argv)
        assert "redis-password is not supported" in str(error.value)
        assert "Traceback" not in str(error.value)
        assert_no_secret(str(error.value))
        assert_no_secret(repr(error.value))
        assert error.value.__cause__ is None

        with pytest.raises(SystemExit) as exit_info:
            main(argv)
        assert exit_info.value.code == 2
        captured = capsys.readouterr()
        assert "Traceback" not in captured.out
        assert "Traceback" not in captured.err
        assert_no_secret(captured.out)
        assert_no_secret(captured.err)
        assert_no_secret(str(exit_info.value))
