from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import quote, unquote, urlparse, urlunparse


class RedisRelaySettingsContractError(ValueError):
    pass


@dataclass(frozen=True)
class RedisRelaySettings:
    enabled: bool
    target_url: str
    target_username: str
    target_tls: bool
    scope: str
    include_recorder_network_context: bool
    interval_seconds: float
    scan_count: int

    def as_api_document(self, *, password_configured: bool) -> dict[str, object]:
        return {
            "enabled": self.enabled,
            "target": {
                "url": self.target_url,
                "username": self.target_username,
                "passwordConfigured": password_configured,
                "tls": self.target_tls,
            },
            "scope": self.scope,
            "includeRecorderNetworkContext": self.include_recorder_network_context,
            "intervalSeconds": self.interval_seconds,
            "scanCount": self.scan_count,
        }


def validated_redis_relay_settings(document: object) -> tuple[RedisRelaySettings, str | None, bool]:
    if not isinstance(document, dict):
        raise RedisRelaySettingsContractError("redis relay settings must be an object")
    target = document.get("target")
    if not isinstance(target, dict):
        raise RedisRelaySettingsContractError("redis relay target must be an object")
    enabled = _bool(document, "enabled")
    url = _string(target, "url").strip()
    username = _string(target, "username").strip()
    tls = _bool(target, "tls")
    password = target.get("password")
    if password is not None and not isinstance(password, str):
        raise RedisRelaySettingsContractError("redis relay target password must be a string")
    clear_password = target.get("clearPassword", False)
    if not isinstance(clear_password, bool):
        raise RedisRelaySettingsContractError("redis relay target clearPassword must be a boolean")
    if password and clear_password:
        raise RedisRelaySettingsContractError(
            "redis relay target password and clearPassword are mutually exclusive"
        )
    for name, value in (("url", url), ("username", username), ("password", password or "")):
        if "\n" in value or "\r" in value:
            raise RedisRelaySettingsContractError(
                f"redis relay target {name} must not contain a newline"
            )
    normalized_url = normalized_target_url(url, username=username, tls=tls)
    scope = _string(document, "scope")
    if scope not in {"waveform_trend_only", "vital_reconstruction"}:
        raise RedisRelaySettingsContractError("redis relay scope is invalid")
    include_context = _bool(document, "includeRecorderNetworkContext")
    interval = document.get("intervalSeconds")
    if isinstance(interval, bool) or not isinstance(interval, (int, float)) or interval < 0.1:
        raise RedisRelaySettingsContractError(
            "redis relay intervalSeconds must be a number greater than or equal to 0.1"
        )
    scan_count = document.get("scanCount")
    if isinstance(scan_count, bool) or not isinstance(scan_count, int) or scan_count < 1:
        raise RedisRelaySettingsContractError(
            "redis relay scanCount must be an integer greater than or equal to 1"
        )
    if enabled and not url:
        raise RedisRelaySettingsContractError(
            "redis relay target url is required when enabled"
        )
    return (
        RedisRelaySettings(
            enabled=enabled,
            target_url=normalized_url,
            target_username=username,
            target_tls=tls,
            scope=scope,
            include_recorder_network_context=include_context,
            interval_seconds=float(interval),
            scan_count=scan_count,
        ),
        password if password else None,
        clear_password,
    )


def normalized_target_url(url: str, *, username: str, tls: bool) -> str:
    if not url:
        return ""
    parsed = urlparse(url)
    if parsed.scheme not in {"redis", "rediss"}:
        raise RedisRelaySettingsContractError(
            "redis relay target url scheme must be redis or rediss"
        )
    if not parsed.hostname:
        raise RedisRelaySettingsContractError("redis relay target url host is required")
    try:
        port = parsed.port
    except ValueError as error:
        raise RedisRelaySettingsContractError(
            "redis relay target url port is invalid"
        ) from error
    path = parsed.path or ""
    if path not in {"", "/"}:
        database = path.removeprefix("/")
        if "/" in database or not database.isdigit():
            raise RedisRelaySettingsContractError(
                "redis relay target url database path must be /<number>"
            )
    host = parsed.hostname
    if ":" in host and not host.startswith("["):
        host = f"[{host}]"
    authority = host
    if port is not None:
        authority += f":{port}"
    effective_username = username or (unquote(parsed.username) if parsed.username else "")
    if effective_username:
        authority = f"{quote(effective_username, safe='')}@{authority}"
    return urlunparse(("rediss" if tls else "redis", authority, path, "", parsed.query, ""))


def _string(document: dict[str, object], name: str) -> str:
    value = document.get(name)
    if not isinstance(value, str):
        raise RedisRelaySettingsContractError(f"redis relay {name} must be a string")
    return value


def _bool(document: dict[str, object], name: str) -> bool:
    value = document.get(name)
    if not isinstance(value, bool):
        raise RedisRelaySettingsContractError(f"redis relay {name} must be a boolean")
    return value
