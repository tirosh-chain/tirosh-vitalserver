from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass


@dataclass(frozen=True)
class ObserverSettings:
    host: str
    port: int
    redis_host: str
    redis_port: int
    redis_timeout_seconds: float
    recorder_online_threshold_seconds: int
    access_log_path: str
    access_log_limit: int


def load_settings(environ: Mapping[str, str] | None = None) -> ObserverSettings:
    env = environ if environ is not None else os.environ
    return ObserverSettings(
        host=env.get("VITALDB_OBSERVER_HOST", "127.0.0.1"),
        port=_int_env(env, "VITALDB_OBSERVER_PORT", 8080),
        redis_host=env.get("VITALDB_OBSERVER_REDIS_HOST", "redis"),
        redis_port=_int_env(env, "VITALDB_OBSERVER_REDIS_PORT", 6379),
        redis_timeout_seconds=_float_env(
            env, "VITALDB_OBSERVER_REDIS_TIMEOUT_SECONDS", 2.0
        ),
        recorder_online_threshold_seconds=_int_env(
            env,
            "VITALDB_OBSERVER_RECORDER_ONLINE_THRESHOLD_SECONDS",
            120,
        ),
        access_log_path=env.get("VITALDB_OBSERVER_ACCESS_LOG_PATH", ""),
        access_log_limit=_int_env(env, "VITALDB_OBSERVER_ACCESS_LOG_LIMIT", 200),
    )


def _int_env(env: Mapping[str, str], key: str, default: int) -> int:
    raw_value = env.get(key)
    if raw_value is None or raw_value == "":
        return default
    return int(raw_value)


def _float_env(env: Mapping[str, str], key: str, default: float) -> float:
    raw_value = env.get(key)
    if raw_value is None or raw_value == "":
        return default
    return float(raw_value)
