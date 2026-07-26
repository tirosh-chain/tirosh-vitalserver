from __future__ import annotations

import os
import tempfile
import tomllib
from pathlib import Path
from typing import Any

from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.redis_relay_settings import (
    RedisRelaySettings,
    RedisRelaySettingsContractError,
    validated_redis_relay_settings,
)


class FileRedisRelaySettingsRepository:
    def __init__(self, config_path: Path, password_path: Path) -> None:
        self._config_path = config_path
        self._password_path = password_path

    def read(self) -> dict[str, object]:
        document = self._read_toml()
        relay = _table(document, "redis_relay", self._config_path)
        target = _table(document, "target", self._config_path)
        password_file = target.get("password_file")
        if password_file is not None and not isinstance(password_file, str):
            raise _invalid("target.password_file must be a string", self._config_path)
        password_configured = False
        if password_file:
            if Path(password_file).name != "redis-relay-target-password":
                raise _invalid("target.password_file is not the Runtime secret contract", self._config_path)
            password_configured = self._require_password_file()
        url = _required_string(target, "url", self._config_path)
        parsed_username = _url_username(url)
        settings_document: dict[str, object] = {
            "enabled": _required_bool(relay, "enabled", self._config_path),
            "target": {
                "url": url,
                "username": parsed_username,
                "tls": url.startswith("rediss://"),
                "password": "",
                "clearPassword": False,
            },
            "scope": _required_string(relay, "scope", self._config_path),
            "includeRecorderNetworkContext": _required_bool(
                relay, "include_recorder_network_context", self._config_path
            ),
            "intervalSeconds": _required_number(
                relay, "interval_seconds", self._config_path
            ),
            "scanCount": _required_int(relay, "scan_count", self._config_path),
        }
        try:
            settings, _, _ = validated_redis_relay_settings(settings_document)
        except RedisRelaySettingsContractError as error:
            raise _invalid(str(error), self._config_path) from error
        return settings.as_api_document(password_configured=password_configured)

    def save(self, document: dict[str, object]) -> None:
        settings, password, clear_password = validated_redis_relay_settings(document)
        current = self.read()
        current_target = current["target"]
        assert isinstance(current_target, dict)
        password_configured = bool(current_target["passwordConfigured"])
        if password is not None:
            self._atomic_write(self._password_path, password, mode=0o600)
            password_configured = True
        if clear_password:
            password_configured = False
        self._atomic_write(
            self._config_path,
            _toml(settings, password_configured=password_configured),
            mode=0o600,
        )
        if clear_password:
            try:
                self._password_path.unlink(missing_ok=True)
            except OSError as error:
                raise GuestControlDependencyError(
                    f"redis relay password removal failed path={self._password_path}: {error}",
                    kind="redisRelayPasswordWriteFailed",
                ) from error

    def _read_toml(self) -> dict[str, Any]:
        try:
            text = self._config_path.read_text(encoding="utf-8")
        except FileNotFoundError as error:
            raise GuestControlDependencyError(
                f"redis relay settings file is missing: {self._config_path}",
                kind="redisRelaySettingsMissing",
            ) from error
        except OSError as error:
            raise GuestControlDependencyError(
                f"redis relay settings read failed path={self._config_path}: {error}",
                kind="redisRelaySettingsReadFailed",
            ) from error
        try:
            document = tomllib.loads(text)
        except (tomllib.TOMLDecodeError, ValueError) as error:
            raise _invalid(str(error), self._config_path) from error
        return document

    def _require_password_file(self) -> bool:
        try:
            password = self._password_path.read_text(encoding="utf-8")
        except FileNotFoundError as error:
            raise GuestControlDependencyError(
                f"redis relay password is configured but missing: {self._password_path}",
                kind="redisRelayPasswordMissing",
            ) from error
        except OSError as error:
            raise GuestControlDependencyError(
                f"redis relay password read failed path={self._password_path}: {error}",
                kind="redisRelayPasswordReadFailed",
            ) from error
        if not password.rstrip("\n"):
            raise GuestControlDependencyError(
                f"redis relay password file is empty: {self._password_path}",
                kind="redisRelayPasswordInvalid",
            )
        return True

    def _atomic_write(self, path: Path, content: str, *, mode: int) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary: str | None = None
        try:
            descriptor, temporary = tempfile.mkstemp(
                dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
            )
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                stream.write(content)
                if not content.endswith("\n"):
                    stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, mode)
            os.replace(temporary, path)
        except OSError as error:
            if temporary is not None:
                try:
                    os.unlink(temporary)
                except FileNotFoundError:
                    pass
            raise GuestControlDependencyError(
                f"redis relay settings write failed path={path}: {error}",
                kind="redisRelaySettingsWriteFailed",
            ) from error


def _toml(settings: RedisRelaySettings, *, password_configured: bool) -> str:
    lines = [
        "[redis_relay]",
        f"enabled = {str(settings.enabled).lower()}",
        f'scope = "{settings.scope}"',
        f"include_recorder_network_context = {str(settings.include_recorder_network_context).lower()}",
        f"interval_seconds = {settings.interval_seconds}",
        f"scan_count = {settings.scan_count}",
        "",
        "[source]",
        'host = "redis"',
        "port = 6379",
        "database = 0",
        "",
        "[target]",
        f'url = "{_toml_escape(settings.target_url)}"',
    ]
    if password_configured:
        lines.append('password_file = "/run/tirosh/secrets/redis-relay-target-password"')
    lines.extend(
        [
            "",
            "[publish]",
            'target_key_prefix = "vitalserver:"',
            'event_stream_key = "vitalserver:relay:events"',
            'fingerprint_hash_key = "vitalserver:relay:fingerprints"',
            'publish_dedupe_hash_key = "vitalserver:relay:published"',
            "event_stream_maxlen = 100000",
            'publisher_id = "vitalserver-helper-relay"',
            "",
        ]
    )
    return "\n".join(lines)


def _toml_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _url_username(url: str) -> str:
    from urllib.parse import unquote, urlparse

    parsed = urlparse(url)
    return unquote(parsed.username) if parsed.username else ""


def _table(document: dict[str, Any], name: str, path: Path) -> dict[str, Any]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise _invalid(f"{name} table is required", path)
    return value


def _required_string(document: dict[str, Any], name: str, path: Path) -> str:
    value = document.get(name)
    if not isinstance(value, str):
        raise _invalid(f"{name} must be a string", path)
    return value


def _required_bool(document: dict[str, Any], name: str, path: Path) -> bool:
    value = document.get(name)
    if not isinstance(value, bool):
        raise _invalid(f"{name} must be a boolean", path)
    return value


def _required_number(document: dict[str, Any], name: str, path: Path) -> float:
    value = document.get(name)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid(f"{name} must be a number", path)
    return float(value)


def _required_int(document: dict[str, Any], name: str, path: Path) -> int:
    value = document.get(name)
    if isinstance(value, bool) or not isinstance(value, int):
        raise _invalid(f"{name} must be an integer", path)
    return value


def _invalid(reason: str, path: Path) -> GuestControlDependencyError:
    return GuestControlDependencyError(
        f"redis relay settings are invalid path={path}: {reason}",
        kind="redisRelaySettingsInvalid",
    )
