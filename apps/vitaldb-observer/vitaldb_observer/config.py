from __future__ import annotations

import argparse
import math
import os
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from .redis_client import RedisEndpoint


class ObserverSettingsError(ValueError):
    pass


@dataclass(frozen=True)
class ObserverSettings:
    host: str
    port: int
    redis_host: str
    redis_port: int
    redis_timeout_seconds: float
    recorder_online_threshold_seconds: int
    recorder_activity_window_seconds: int
    audit_redis_list: str
    audit_event_limit: int
    access_log_path: str
    access_log_limit: int
    redis_endpoint: RedisEndpoint
    redis_database: int = 0
    redis_password_file: str | None = None


def load_settings(
    environ: Mapping[str, str] | None = None,
    argv: Sequence[str] | None = None,
) -> ObserverSettings:
    env = environ if environ is not None else os.environ
    args = [] if argv is None else list(argv)
    _reject_password_value_argv(args)
    parsed = _cli_parser().parse_args(args)
    password_file = _optional_path(
        "redis-password-file",
        parsed.redis_password_file,
        env,
        "VITALDB_OBSERVER_REDIS_PASSWORD_FILE",
    )
    password = _read_password_file(password_file) if password_file is not None else None
    redis_host = _string_setting(
        "redis-host",
        parsed.redis_host,
        env,
        "VITALDB_OBSERVER_REDIS_HOST",
        "redis",
    )
    redis_port = _int_setting(
        "redis-port",
        parsed.redis_port,
        env,
        "VITALDB_OBSERVER_REDIS_PORT",
        6379,
        minimum=1,
        maximum=65535,
    )
    redis_database = _int_setting(
        "redis-database",
        parsed.redis_database,
        env,
        "VITALDB_OBSERVER_REDIS_DATABASE",
        0,
        minimum=0,
    )
    redis_timeout_seconds = _float_setting(
        "redis-timeout-seconds",
        None,
        env,
        "VITALDB_OBSERVER_REDIS_TIMEOUT_SECONDS",
        2.0,
    )
    return ObserverSettings(
        host=_string_setting(
            "host", parsed.host, env, "VITALDB_OBSERVER_HOST", "127.0.0.1"
        ),
        port=_int_setting(
            "port",
            parsed.port,
            env,
            "VITALDB_OBSERVER_PORT",
            8080,
            minimum=1,
            maximum=65535,
        ),
        redis_host=redis_host,
        redis_port=redis_port,
        redis_timeout_seconds=redis_timeout_seconds,
        recorder_online_threshold_seconds=_int_setting(
            "recorder-online-threshold-seconds",
            None,
            env,
            "VITALDB_OBSERVER_RECORDER_ONLINE_THRESHOLD_SECONDS",
            120,
            minimum=0,
        ),
        recorder_activity_window_seconds=_int_setting(
            "recorder-activity-window-seconds",
            None,
            env,
            "VITALDB_OBSERVER_RECORDER_ACTIVITY_WINDOW_SECONDS",
            300,
            minimum=1,
        ),
        audit_redis_list=_string_setting(
            "audit-redis-list",
            None,
            env,
            "VITALDB_OBSERVER_AUDIT_REDIS_LIST",
            "vitalserver:audit_events",
        ),
        audit_event_limit=_int_setting(
            "audit-event-limit",
            None,
            env,
            "VITALDB_OBSERVER_AUDIT_EVENT_LIMIT",
            10000,
            minimum=1,
        ),
        access_log_path=_string_setting(
            "access-log-path",
            parsed.access_log_path,
            env,
            "VITALDB_OBSERVER_ACCESS_LOG_PATH",
            "",
        ),
        access_log_limit=_int_setting(
            "access-log-limit",
            None,
            env,
            "VITALDB_OBSERVER_ACCESS_LOG_LIMIT",
            200,
            minimum=1,
        ),
        redis_database=redis_database,
        redis_password_file=password_file,
        redis_endpoint=RedisEndpoint(
            host=redis_host,
            port=redis_port,
            timeout_seconds=redis_timeout_seconds,
            database=redis_database,
            password=password,
        ),
    )


def _reject_password_value_argv(argv: Sequence[str]) -> None:
    for argument in argv:
        if argument == "--redis-password" or argument.startswith("--redis-password="):
            raise ObserverSettingsError(
                "redis-password is not supported; use --redis-password-file"
            )


def _cli_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vitaldb-observer",
        description="VitalDB observer",
        allow_abbrev=False,
    )
    parser.add_argument("--host")
    parser.add_argument("--port")
    parser.add_argument("--redis-host")
    parser.add_argument("--redis-port")
    parser.add_argument("--redis-database")
    parser.add_argument("--redis-password-file")
    parser.add_argument("--access-log-path")
    return parser


def _raw_value(cli: str | None, env: Mapping[str, str], env_key: str) -> str | None:
    if cli is not None:
        return cli
    if env_key in env:
        return env[env_key]
    return None


def _string_setting(
    field: str,
    cli: str | None,
    env: Mapping[str, str],
    env_key: str,
    default: str,
) -> str:
    raw = _raw_value(cli, env, env_key)
    if raw is None:
        return default
    if raw.strip() == "":
        raise ObserverSettingsError(f"{field} is empty")
    return raw


def _optional_path(
    field: str,
    cli: str | None,
    env: Mapping[str, str],
    env_key: str,
) -> str | None:
    raw = _raw_value(cli, env, env_key)
    if raw is None:
        return None
    if raw.strip() == "":
        raise ObserverSettingsError(f"{field} must not be empty")
    return raw


def _int_setting(
    field: str,
    cli: str | None,
    env: Mapping[str, str],
    env_key: str,
    default: int,
    *,
    minimum: int,
    maximum: int | None = None,
) -> int:
    raw = _raw_value(cli, env, env_key)
    if raw is None:
        return default
    if raw.strip() == "":
        raise ObserverSettingsError(f"{field} is empty")
    try:
        value = int(raw.strip(), 10)
    except ValueError:
        raise ObserverSettingsError(f"{field} is invalid") from None
    if value < minimum:
        raise ObserverSettingsError(f"{field} must be >= {minimum}")
    if maximum is not None and value > maximum:
        raise ObserverSettingsError(f"{field} must be <= {maximum}")
    return value


def _float_setting(
    field: str,
    cli: str | None,
    env: Mapping[str, str],
    env_key: str,
    default: float,
) -> float:
    raw = _raw_value(cli, env, env_key)
    if raw is None:
        return default
    if raw.strip() == "":
        raise ObserverSettingsError(f"{field} is empty")
    try:
        value = float(raw.strip())
    except ValueError:
        raise ObserverSettingsError(f"{field} is invalid") from None
    if not math.isfinite(value):
        raise ObserverSettingsError(f"{field} must be a finite number")
    if value <= 0:
        raise ObserverSettingsError(f"{field} must be > 0")
    return value


def _read_password_file(path: str) -> str:
    try:
        raw = Path(path).read_bytes()
    except ValueError:
        raise ObserverSettingsError("redis-password-file is invalid") from None
    except FileNotFoundError:
        raise ObserverSettingsError("redis-password-file is missing") from None
    except OSError:
        raise ObserverSettingsError("redis-password-file read failed") from None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise ObserverSettingsError("redis-password-file is not valid UTF-8") from None
    if text.endswith("\r\n"):
        text = text[:-2]
    elif text.endswith("\n"):
        text = text[:-1]
    if text == "":
        raise ObserverSettingsError("redis-password-file is empty")
    return text
