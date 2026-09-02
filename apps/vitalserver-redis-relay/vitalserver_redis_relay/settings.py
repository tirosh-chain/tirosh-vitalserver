from __future__ import annotations

import math
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

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

    def __repr__(self) -> str:
        return (
            "RedisEndpoint("
            f"host={self.host!r}, "
            f"port={self.port}, "
            f"database={self.database}, "
            f"username_configured={self.username is not None}, "
            f"password_configured={self.password is not None}, "
            f"tls={self.tls})"
        )


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
    source: RedisEndpoint | None
    target: RedisEndpoint | None
    publish_contract: RelayPublishContract
    scope: RelayScope
    include_recorder_network_context: bool
    interval_seconds: float
    scan_count: int
    status_interval_seconds: float


def load_settings(path: Path) -> RelaySettings:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise RelaySettingsError("relay config file is missing") from None
    except OSError:
        raise RelaySettingsError("relay config read failed") from None
    except UnicodeDecodeError:
        raise RelaySettingsError("relay config is not valid UTF-8") from None
    try:
        data = tomllib.loads(raw)
    except tomllib.TOMLDecodeError:
        raise RelaySettingsError("relay config is invalid TOML") from None
    return parse_settings(data, base_dir=path.parent)


def parse_settings(data: dict[str, Any], *, base_dir: Path) -> RelaySettings:
    relay = _table(data, "redis_relay")
    enabled = _required_bool(relay, "enabled", label="redis_relay.enabled")
    publish_contract = _publish_contract(_table(data, "publish", default={}))
    source: RedisEndpoint | None = None
    target: RedisEndpoint | None = None
    if enabled:
        source = _source_endpoint(_table(data, "source"), base_dir=base_dir)
        target = _target_endpoint(_table(data, "target"), base_dir=base_dir)

    return RelaySettings(
        enabled=enabled,
        source=source,
        target=target,
        publish_contract=publish_contract,
        scope=_relay_scope(relay),
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


def _source_endpoint(data: dict[str, Any], *, base_dir: Path) -> RedisEndpoint:
    if "username" in data:
        raise RelaySettingsError(
            "source.username is not supported; Redis 3.2 uses password-only AUTH"
        )
    if "username_file" in data:
        raise RelaySettingsError(
            "source.username_file is not supported; Redis 3.2 uses password-only AUTH"
        )
    if "password" in data:
        raise RelaySettingsError(
            "source.password is not supported; use source.password_file"
        )
    host = _required_non_empty_field(data, "host", label="source.host")
    password_file = _optional_credential_path(
        data,
        "password_file",
        field="source.password_file",
    )
    password = (
        _read_secret_file(
            password_file,
            base_dir=base_dir,
            field="source.password_file",
        )
        if password_file is not None
        else None
    )
    return RedisEndpoint(
        host=host,
        port=_int(data, "port", default=6379, minimum=1, maximum=65535),
        database=_int(data, "database", default=0, minimum=0),
        username=None,
        password=password,
        tls=_bool(data, "tls", default=False),
    )


def _target_endpoint(data: dict[str, Any], *, base_dir: Path) -> RedisEndpoint:
    if "username" in data:
        raise RelaySettingsError(
            "target.username is not supported; use target.username_file"
        )
    if "password" in data:
        raise RelaySettingsError(
            "target.password is not supported; use target.password_file"
        )
    url = _optional_str(data, "url")
    if not url:
        raise RelaySettingsError("target.url is required when redis relay is enabled")
    endpoint = _endpoint_from_url(url)
    username_file = _optional_credential_path(
        data,
        "username_file",
        field="target.username_file",
    )
    username = (
        _read_secret_file(
            username_file,
            base_dir=base_dir,
            field="target.username_file",
        )
        if username_file is not None
        else None
    )
    password_file = _optional_credential_path(
        data,
        "password_file",
        field="target.password_file",
    )
    password = (
        _read_secret_file(
            password_file,
            base_dir=base_dir,
            field="target.password_file",
        )
        if password_file is not None
        else None
    )
    if username is not None and password is None:
        raise RelaySettingsError("target username requires target.password_file")
    return RedisEndpoint(
        host=endpoint.host,
        port=endpoint.port,
        database=endpoint.database,
        username=username,
        password=password,
        tls=endpoint.tls,
    )


def _endpoint_from_url(url: str) -> RedisEndpoint:
    try:
        parsed = urlparse(url)
        scheme = parsed.scheme
        hostname = parsed.hostname
        password = parsed.password
        username = parsed.username
        path = parsed.path
        netloc = parsed.netloc
        query = parsed.query
        params = parsed.params
        fragment = parsed.fragment
    except ValueError:
        raise RelaySettingsError("target.url is invalid") from None
    try:
        port = parsed.port
    except ValueError:
        raise RelaySettingsError("target.url port is invalid") from None
    if scheme not in {"redis", "rediss"}:
        raise RelaySettingsError("target.url scheme must be redis or rediss")
    if not hostname:
        raise RelaySettingsError("target.url host is required")
    if password is not None:
        raise RelaySettingsError("target.url must not contain a password")
    if username is not None:
        raise RelaySettingsError("target.url must not contain a username")
    if query:
        raise RelaySettingsError("target.url must not contain a query")
    if params or (path is not None and ";" in path):
        raise RelaySettingsError("target.url must not contain params")
    if fragment:
        raise RelaySettingsError("target.url must not contain a fragment")
    database = 0
    if path and path != "/":
        raw_database = path.removeprefix("/")
        if "/" in raw_database:
            raise RelaySettingsError("target.url database path must be /<number>")
        try:
            database = int(raw_database)
        except ValueError:
            raise RelaySettingsError("target.url database must be an integer") from None
        if database < 0:
            raise RelaySettingsError("target.url database must be >= 0")
    if port is None:
        if netloc.endswith(":"):
            raise RelaySettingsError("target.url port is invalid")
        resolved_port = 6379
    elif port < 1 or port > 65535:
        raise RelaySettingsError("target.url port is invalid")
    else:
        resolved_port = port
    return RedisEndpoint(
        host=hostname,
        port=resolved_port,
        database=database,
        username=None,
        password=None,
        tls=scheme == "rediss",
    )


def _relay_scope(relay: dict[str, Any]) -> RelayScope:
    raw = _str(relay, "scope", default=RelayScope.VITAL_RECONSTRUCTION)
    try:
        return RelayScope(raw)
    except ValueError:
        raise RelaySettingsError("redis_relay.scope is invalid") from None


def _read_secret_file(path: str, *, base_dir: Path, field: str) -> str:
    try:
        secret_path = Path(path)
        if not secret_path.is_absolute():
            secret_path = base_dir / secret_path
        raw = secret_path.read_bytes()
    except ValueError:
        raise RelaySettingsError(f"{field} is invalid") from None
    except FileNotFoundError:
        raise RelaySettingsError(f"{field} is missing") from None
    except OSError:
        raise RelaySettingsError(f"{field} read failed") from None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise RelaySettingsError(f"{field} is not valid UTF-8") from None
    if text.endswith("\r\n"):
        text = text[:-2]
    elif text.endswith("\n"):
        text = text[:-1]
    if text == "":
        raise RelaySettingsError(f"{field} is empty")
    return text


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


def _required_non_empty_field(
    data: dict[str, Any],
    name: str,
    *,
    label: str,
) -> str:
    if name not in data:
        raise RelaySettingsError(f"{label} is required")
    value = data[name]
    if not isinstance(value, str):
        raise RelaySettingsError(f"{label} must be a string")
    stripped = value.strip()
    if not stripped:
        raise RelaySettingsError(f"{label} must not be empty")
    return stripped


def _optional_str(data: dict[str, Any], name: str) -> str | None:
    value = data.get(name)
    if value is None or value == "":
        return None
    if not isinstance(value, str):
        raise RelaySettingsError(f"{name} must be a string")
    return value


def _optional_credential_path(
    data: dict[str, Any],
    name: str,
    *,
    field: str,
) -> str | None:
    if name not in data:
        return None
    value = data[name]
    if not isinstance(value, str):
        raise RelaySettingsError(f"{field} must be a string")
    if value == "" or value.strip() == "":
        raise RelaySettingsError(f"{field} must not be empty")
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
    if isinstance(value, bool) or not isinstance(value, int):
        raise RelaySettingsError(f"{name} must be an integer")
    if value < minimum:
        raise RelaySettingsError(f"{name} must be >= {minimum}")
    return value


def _required_bool(data: dict[str, Any], name: str, *, label: str) -> bool:
    if name not in data:
        raise RelaySettingsError(f"{label} is required")
    value = data[name]
    if not isinstance(value, bool):
        raise RelaySettingsError(f"{label} must be a boolean")
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
    if isinstance(value, bool) or not isinstance(value, int):
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
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise RelaySettingsError(f"{name} must be numeric")
    numeric = float(value)
    if not math.isfinite(numeric):
        raise RelaySettingsError(f"{name} must be a finite number")
    if numeric < minimum:
        raise RelaySettingsError(f"{name} must be >= {minimum}")
    return numeric
