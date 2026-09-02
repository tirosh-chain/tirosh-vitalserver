from __future__ import annotations

import math
from dataclasses import dataclass
from urllib.parse import unquote, urlparse, urlunparse


class RedisRelaySettingsContractError(ValueError):
    pass


TARGET_USERNAME_FILE_CONTRACT = "/run/tirosh/secrets/redis-relay-target-username"
TARGET_PASSWORD_FILE_CONTRACT = "/run/tirosh/secrets/redis-relay-target-password"


def credential_text_without_one_trailing_newline(text: str) -> str:
    if text.endswith("\r\n"):
        return text[:-2]
    if text.endswith("\n"):
        return text[:-1]
    return text


@dataclass(frozen=True)
class RedisRelaySettings:
    enabled: bool
    target_url: str
    target_tls: bool
    scope: str
    include_recorder_network_context: bool
    interval_seconds: float
    scan_count: int

    def as_api_document(
        self,
        *,
        username_configured: bool,
        password_configured: bool,
    ) -> dict[str, object]:
        return {
            "enabled": self.enabled,
            "target": {
                "url": self.target_url,
                "usernameConfigured": username_configured,
                "passwordConfigured": password_configured,
                "tls": self.target_tls,
            },
            "scope": self.scope,
            "includeRecorderNetworkContext": self.include_recorder_network_context,
            "intervalSeconds": self.interval_seconds,
            "scanCount": self.scan_count,
        }


@dataclass(frozen=True)
class RedisRelaySettingsApply:
    settings: RedisRelaySettings
    username: str | None
    clear_username: bool
    password: str | None
    clear_password: bool


@dataclass(frozen=True)
class RedisRelayTargetURL:
    canonical_url: str
    tls: bool
    legacy_username: str | None


def validated_redis_relay_settings(document: object) -> RedisRelaySettingsApply:
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
        raise RedisRelaySettingsContractError(
            "redis relay target password must be a string"
        )
    clear_password = target.get("clearPassword", False)
    if not isinstance(clear_password, bool):
        raise RedisRelaySettingsContractError(
            "redis relay target clearPassword must be a boolean"
        )
    clear_username = target.get("clearUsername", False)
    if not isinstance(clear_username, bool):
        raise RedisRelaySettingsContractError(
            "redis relay target clearUsername must be a boolean"
        )
    if password and clear_password:
        raise RedisRelaySettingsContractError(
            "redis relay target password and clearPassword are mutually exclusive"
        )
    if username and clear_username:
        raise RedisRelaySettingsContractError(
            "redis relay target username and clearUsername are mutually exclusive"
        )
    for name, value in (
        ("url", url),
        ("username", username),
        ("password", password or ""),
    ):
        if "\n" in value or "\r" in value:
            raise RedisRelaySettingsContractError(
                f"redis relay target {name} must not contain a newline"
            )
    parsed = (
        parse_target_url(url, tls=tls) if url else RedisRelayTargetURL("", tls, None)
    )
    if parsed.legacy_username is not None:
        raise RedisRelaySettingsContractError(
            "redis relay target url must not contain user-info"
        )
    scope = _string(document, "scope")
    if scope not in {"waveform_trend_only", "vital_reconstruction"}:
        raise RedisRelaySettingsContractError("redis relay scope is invalid")
    include_context = _bool(document, "includeRecorderNetworkContext")
    interval = document.get("intervalSeconds")
    if isinstance(interval, bool) or not isinstance(interval, (int, float)):
        raise RedisRelaySettingsContractError(
            "redis relay intervalSeconds must be a number greater than or equal to 0.1"
        )
    numeric_interval = float(interval)
    if not math.isfinite(numeric_interval):
        raise RedisRelaySettingsContractError(
            "redis relay intervalSeconds must be a finite number"
        )
    if numeric_interval < 0.1:
        raise RedisRelaySettingsContractError(
            "redis relay intervalSeconds must be a number greater than or equal to 0.1"
        )
    scan_count = document.get("scanCount")
    if (
        isinstance(scan_count, bool)
        or not isinstance(scan_count, int)
        or scan_count < 1
    ):
        raise RedisRelaySettingsContractError(
            "redis relay scanCount must be an integer greater than or equal to 1"
        )
    if enabled and not url:
        raise RedisRelaySettingsContractError(
            "redis relay target url is required when enabled"
        )
    return RedisRelaySettingsApply(
        settings=RedisRelaySettings(
            enabled=enabled,
            target_url=parsed.canonical_url,
            target_tls=tls,
            scope=scope,
            include_recorder_network_context=include_context,
            interval_seconds=numeric_interval,
            scan_count=scan_count,
        ),
        username=username or None,
        clear_username=clear_username,
        password=password if password else None,
        clear_password=clear_password,
    )


def parse_target_url(url: str, *, tls: bool) -> RedisRelayTargetURL:
    if not url:
        return RedisRelayTargetURL("", tls, None)
    try:
        parsed = urlparse(url)
        scheme = parsed.scheme
        hostname = parsed.hostname
        password = parsed.password
        username = parsed.username
        path = parsed.path or ""
        netloc = parsed.netloc
        query = parsed.query
        params = parsed.params
        fragment = parsed.fragment
    except ValueError:
        raise RedisRelaySettingsContractError(
            "redis relay target url is invalid"
        ) from None
    try:
        port = parsed.port
    except ValueError:
        raise RedisRelaySettingsContractError(
            "redis relay target url port is invalid"
        ) from None
    if scheme not in {"redis", "rediss"}:
        raise RedisRelaySettingsContractError(
            "redis relay target url scheme must be redis or rediss"
        )
    if not hostname:
        raise RedisRelaySettingsContractError("redis relay target url host is required")
    if password is not None:
        raise RedisRelaySettingsContractError(
            "redis relay target url must not contain a password"
        )
    if query:
        raise RedisRelaySettingsContractError(
            "redis relay target url must not contain a query"
        )
    if params or ";" in path:
        raise RedisRelaySettingsContractError(
            "redis relay target url must not contain params"
        )
    if fragment:
        raise RedisRelaySettingsContractError(
            "redis relay target url must not contain a fragment"
        )
    if path not in {"", "/"}:
        database = path.removeprefix("/")
        if "/" in database or not database.isdigit():
            raise RedisRelaySettingsContractError(
                "redis relay target url database path must be /<number>"
            )
    if port is None and netloc.endswith(":"):
        raise RedisRelaySettingsContractError("redis relay target url port is invalid")
    host = hostname
    if ":" in host and not host.startswith("["):
        host = f"[{host}]"
    authority = host
    if port is not None:
        if port < 1 or port > 65535:
            raise RedisRelaySettingsContractError(
                "redis relay target url port is invalid"
            )
        authority += f":{port}"
    canonical = urlunparse(("rediss" if tls else "redis", authority, path, "", "", ""))
    legacy_username = unquote(username) if username else None
    if legacy_username == "":
        legacy_username = None
    if username is not None and legacy_username is None:
        raise RedisRelaySettingsContractError(
            "redis relay target url must not contain user-info"
        )
    return RedisRelayTargetURL(canonical, tls, legacy_username)


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
