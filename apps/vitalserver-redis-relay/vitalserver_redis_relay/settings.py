from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

from .key_filter import RelayScope


class RelaySettingsError(ValueError):
    pass


@dataclass(frozen=True)
class RedisEndpoint:
    host: str
    port: int
    database: int
    username: str | None = None
    password: str | None = None
    tls: bool = False


@dataclass(frozen=True)
class RelayPublishContract:
    target_key_prefix: str
    event_stream_key: str
    fingerprint_hash_key: str
    publish_dedupe_hash_key: str
    event_stream_maxlen: int | None
    publisher_id: str


@dataclass(frozen=True)
class RelaySettings:
    enabled: bool
    source: RedisEndpoint
    target: RedisEndpoint | None
    publish_contract: RelayPublishContract
    scope: RelayScope
    include_recorder_network_context: bool
    interval_seconds: float
    scan_count: int
    status_interval_seconds: float


def load_settings(path: Path) -> RelaySettings:
    if not path.exists():
        return disabled_settings()
    try:
        data = tomllib.loads(path.read_text())
    except Exception as error:
        raise RelaySettingsError(f"relay config read failed: {error}") from error
    return parse_settings(data, base_dir=path.parent)


def disabled_settings() -> RelaySettings:
    return RelaySettings(
        enabled=False,
        source=RedisEndpoint(host="redis", port=6379, database=0),
        target=None,
        publish_contract=default_publish_contract(),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=False,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )


def parse_settings(data: dict[str, Any], *, base_dir: Path) -> RelaySettings:
    relay = _table(data, "redis_relay")
    enabled = _bool(relay, "enabled", default=False)
    source = _endpoint(_table(data, "source", default={}), defaults=("redis", 6379, 0))
    target_data = _table(data, "target", default={})
    target = _target_endpoint(target_data, base_dir=base_dir) if enabled else None
    publish_contract = _publish_contract(_table(data, "publish", default={}))

    return RelaySettings(
        enabled=enabled,
        source=source,
        target=target,
        publish_contract=publish_contract,
        scope=RelayScope(_str(relay, "scope", default=RelayScope.VITAL_RECONSTRUCTION)),
        include_recorder_network_context=_bool(
            relay,
            "include_recorder_network_context",
            default=False,
        ),
        interval_seconds=_float(relay, "interval_seconds", default=1.0, minimum=0.1),
        scan_count=_int(relay, "scan_count", default=1000, minimum=1),
        status_interval_seconds=_float(
            relay,
            "status_interval_seconds",
            default=5.0,
            minimum=0.5,
        ),
    )


def default_publish_contract() -> RelayPublishContract:
    return RelayPublishContract(
        target_key_prefix="vitalserver:",
        event_stream_key="vitalserver:relay:events",
        fingerprint_hash_key="vitalserver:relay:fingerprints",
        publish_dedupe_hash_key="vitalserver:relay:published",
        event_stream_maxlen=100_000,
        publisher_id="vitalserver-helper-relay",
    )


def _publish_contract(data: dict[str, Any]) -> RelayPublishContract:
    defaults = default_publish_contract()
    event_stream_maxlen = _optional_int(
        data,
        "event_stream_maxlen",
        default=defaults.event_stream_maxlen,
        minimum=1,
    )
    return RelayPublishContract(
        target_key_prefix=_str(
            data,
            "target_key_prefix",
            default=defaults.target_key_prefix,
        ),
        event_stream_key=_required_non_empty_str(
            data,
            "event_stream_key",
            default=defaults.event_stream_key,
        ),
        fingerprint_hash_key=_required_non_empty_str(
            data,
            "fingerprint_hash_key",
            default=defaults.fingerprint_hash_key,
        ),
        publish_dedupe_hash_key=_required_non_empty_str(
            data,
            "publish_dedupe_hash_key",
            default=defaults.publish_dedupe_hash_key,
        ),
        event_stream_maxlen=event_stream_maxlen,
        publisher_id=_required_non_empty_str(
            data,
            "publisher_id",
            default=defaults.publisher_id,
        ),
    )


def _target_endpoint(data: dict[str, Any], *, base_dir: Path) -> RedisEndpoint:
    endpoint = _endpoint_from_url_or_table(data, defaults=("", 6379, 0))
    if not endpoint.host:
        raise RelaySettingsError("target.url is required when redis relay is enabled")
    password_file = _optional_str(data, "password_file")
    password = _read_password_file(password_file, base_dir=base_dir)
    return RedisEndpoint(
        host=endpoint.host,
        port=endpoint.port,
        database=endpoint.database,
        username=endpoint.username,
        password=password if password_file else endpoint.password,
        tls=endpoint.tls,
    )


def _endpoint(data: dict[str, Any], *, defaults: tuple[str, int, int]) -> RedisEndpoint:
    host, port, database = defaults
    return RedisEndpoint(
        host=_str(data, "host", default=host),
        port=_int(data, "port", default=port, minimum=1, maximum=65535),
        database=_int(data, "database", default=database, minimum=0),
        username=_optional_str(data, "username"),
        tls=_bool(data, "tls", default=False),
    )


def _endpoint_from_url_or_table(
    data: dict[str, Any],
    *,
    defaults: tuple[str, int, int],
) -> RedisEndpoint:
    url = _optional_str(data, "url")
    if url:
        return _endpoint_from_url(url)
    return _endpoint(data, defaults=defaults)


def _endpoint_from_url(url: str) -> RedisEndpoint:
    parsed = urlparse(url)
    if parsed.scheme not in {"redis", "rediss"}:
        raise RelaySettingsError("target.url scheme must be redis or rediss")
    if not parsed.hostname:
        raise RelaySettingsError("target.url host is required")
    database = 0
    if parsed.path and parsed.path != "/":
        raw_database = parsed.path.removeprefix("/")
        if "/" in raw_database:
            raise RelaySettingsError("target.url database path must be /<number>")
        try:
            database = int(raw_database)
        except ValueError as error:
            raise RelaySettingsError(
                "target.url database must be an integer"
            ) from error
        if database < 0:
            raise RelaySettingsError("target.url database must be >= 0")
    try:
        port = parsed.port or 6379
    except ValueError as error:
        raise RelaySettingsError("target.url port is invalid") from error
    return RedisEndpoint(
        host=parsed.hostname,
        port=port,
        database=database,
        username=unquote(parsed.username) if parsed.username else None,
        password=unquote(parsed.password) if parsed.password else None,
        tls=parsed.scheme == "rediss",
    )


def _read_password_file(path: str | None, *, base_dir: Path) -> str | None:
    if not path:
        return None
    password_path = Path(path)
    if not password_path.is_absolute():
        password_path = base_dir / password_path
    try:
        password = password_path.read_text().rstrip("\n")
    except Exception as error:
        message = f"target.password_file read failed: {error}"
        raise RelaySettingsError(message) from error
    return password if password else None


def _table(
    data: dict[str, Any],
    name: str,
    *,
    default: dict[str, Any] | None = None,
) -> dict[str, Any]:
    value = data.get(name, default)
    if value is None:
        raise RelaySettingsError(f"{name} table is required")
    if not isinstance(value, dict):
        raise RelaySettingsError(f"{name} must be a table")
    return value


def _str(data: dict[str, Any], name: str, *, default: str | RelayScope) -> str:
    value = data.get(name, default)
    if isinstance(value, RelayScope):
        return value.value
    if not isinstance(value, str):
        raise RelaySettingsError(f"{name} must be a string")
    return value.strip()


def _required_non_empty_str(
    data: dict[str, Any],
    name: str,
    *,
    default: str,
) -> str:
    value = _str(data, name, default=default)
    if not value:
        raise RelaySettingsError(f"{name} must not be empty")
    return value


def _optional_str(data: dict[str, Any], name: str) -> str | None:
    value = data.get(name)
    if value is None or value == "":
        return None
    if not isinstance(value, str):
        raise RelaySettingsError(f"{name} must be a string")
    return value


def _optional_int(
    data: dict[str, Any],
    name: str,
    *,
    default: int | None,
    minimum: int,
) -> int | None:
    value = data.get(name, default)
    if value is None:
        return None
    if not isinstance(value, int):
        raise RelaySettingsError(f"{name} must be an integer")
    if value < minimum:
        raise RelaySettingsError(f"{name} must be >= {minimum}")
    return value


def _bool(data: dict[str, Any], name: str, *, default: bool) -> bool:
    value = data.get(name, default)
    if not isinstance(value, bool):
        raise RelaySettingsError(f"{name} must be a boolean")
    return value


def _int(
    data: dict[str, Any],
    name: str,
    *,
    default: int,
    minimum: int,
    maximum: int | None = None,
) -> int:
    value = data.get(name, default)
    if not isinstance(value, int):
        raise RelaySettingsError(f"{name} must be an integer")
    if value < minimum:
        raise RelaySettingsError(f"{name} must be >= {minimum}")
    if maximum is not None and value > maximum:
        raise RelaySettingsError(f"{name} must be <= {maximum}")
    return value


def _float(
    data: dict[str, Any],
    name: str,
    *,
    default: float,
    minimum: float,
) -> float:
    value = data.get(name, default)
    if not isinstance(value, int | float):
        raise RelaySettingsError(f"{name} must be numeric")
    numeric = float(value)
    if numeric < minimum:
        raise RelaySettingsError(f"{name} must be >= {minimum}")
    return numeric
