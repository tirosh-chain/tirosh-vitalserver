from __future__ import annotations

import math
import os
import tempfile
import tomllib
from contextlib import suppress
from pathlib import Path
from typing import Any

from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.redis_relay_settings import (
    TARGET_PASSWORD_FILE_CONTRACT,
    TARGET_USERNAME_FILE_CONTRACT,
    RedisRelaySettings,
    RedisRelaySettingsContractError,
    credential_text_without_one_trailing_newline,
    parse_target_url,
    validated_redis_relay_settings,
)


class FileRedisRelaySettingsRepository:
    def __init__(
        self,
        config_path: Path,
        username_path: Path,
        password_path: Path,
    ) -> None:
        self._config_path = config_path
        self._username_path = username_path
        self._password_path = password_path

    def read(self) -> dict[str, object]:
        return self._read_settings()

    def _read_settings(self) -> dict[str, object]:
        document = self._read_toml()
        relay = _table(document, "redis_relay", self._config_path)
        target = _table(document, "target", self._config_path)
        url = _required_string(target, "url", self._config_path)
        try:
            parsed = parse_target_url(url, tls=url.startswith("rediss://"))
        except RedisRelaySettingsContractError as error:
            raise _invalid(str(error), self._config_path) from error
        if parsed.legacy_username is not None:
            raise _invalid(
                "target.url username requires migration",
                self._config_path,
            )
        username_configured = self._configured_secret(
            target.get("username_file"),
            expected_contract=TARGET_USERNAME_FILE_CONTRACT,
            path=self._username_path,
            missing_kind="redisRelayUsernameMissing",
            read_kind="redisRelayUsernameReadFailed",
            invalid_kind="redisRelayUsernameInvalid",
            field="target.username_file",
        )
        password_configured = self._configured_secret(
            target.get("password_file"),
            expected_contract=TARGET_PASSWORD_FILE_CONTRACT,
            path=self._password_path,
            missing_kind="redisRelayPasswordMissing",
            read_kind="redisRelayPasswordReadFailed",
            invalid_kind="redisRelayPasswordInvalid",
            field="target.password_file",
        )
        if username_configured and not password_configured:
            raise _invalid(
                "target username requires password_file",
                self._config_path,
            )
        settings_document: dict[str, object] = {
            "enabled": _required_bool(relay, "enabled", self._config_path),
            "target": {
                "url": parsed.canonical_url,
                "username": "",
                "tls": parsed.tls,
                "password": "",
                "clearPassword": False,
                "clearUsername": False,
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
            applied = validated_redis_relay_settings(settings_document)
        except RedisRelaySettingsContractError as error:
            raise _invalid(str(error), self._config_path) from error
        return applied.settings.as_api_document(
            username_configured=username_configured,
            password_configured=password_configured,
        )

    def save(self, document: dict[str, object]) -> None:
        try:
            applied = validated_redis_relay_settings(document)
        except RedisRelaySettingsContractError as error:
            raise _invalid(str(error), self._config_path) from error
        self.migrate_legacy_target_credentials()
        current = self._read_settings()
        current_target = current["target"]
        assert isinstance(current_target, dict)
        username_configured = bool(current_target["usernameConfigured"])
        password_configured = bool(current_target["passwordConfigured"])
        if applied.username is not None:
            username_configured = True
        if applied.clear_username:
            username_configured = False
        if applied.password is not None:
            password_configured = True
        if applied.clear_password:
            password_configured = False
        if username_configured and not password_configured:
            raise _invalid(
                "target username requires password_file",
                self._config_path,
            )
        if applied.username is not None:
            self._atomic_write(
                self._username_path,
                applied.username,
                mode=0o600,
                kind="redisRelayUsernameWriteFailed",
            )
        if applied.password is not None:
            self._atomic_write(
                self._password_path,
                applied.password,
                mode=0o600,
                kind="redisRelayPasswordWriteFailed",
            )
        self._atomic_write(
            self._config_path,
            _toml(
                applied.settings,
                username_configured=username_configured,
                password_configured=password_configured,
            ),
            mode=0o600,
        )
        if applied.clear_username:
            self._remove_secret(
                self._username_path,
                kind="redisRelayUsernameWriteFailed",
            )
        if applied.clear_password:
            self._remove_secret(
                self._password_path,
                kind="redisRelayPasswordWriteFailed",
            )

    def migrate_legacy_target_credentials(self) -> None:
        document = self._read_toml()
        target = _table(document, "target", self._config_path)
        url = _required_string(target, "url", self._config_path)
        try:
            parsed = parse_target_url(url, tls=url.startswith("rediss://"))
        except RedisRelaySettingsContractError as error:
            raise _invalid(str(error), self._config_path) from error
        if parsed.legacy_username is None:
            return
        username_file = target.get("username_file")
        if username_file is not None:
            if not isinstance(username_file, str) or not username_file.strip():
                raise _invalid(
                    "target.username_file must not be empty",
                    self._config_path,
                )
            raise _invalid(
                "target.username_file and target.url username cannot both be set",
                self._config_path,
            )
        password_file = target.get("password_file")
        if password_file is None:
            raise _invalid(
                "target username requires password_file",
                self._config_path,
            )
        self._configured_secret(
            password_file,
            expected_contract=TARGET_PASSWORD_FILE_CONTRACT,
            path=self._password_path,
            missing_kind="redisRelayPasswordMissing",
            read_kind="redisRelayPasswordReadFailed",
            invalid_kind="redisRelayPasswordInvalid",
            field="target.password_file",
        )
        self._atomic_write(
            self._username_path,
            parsed.legacy_username,
            mode=0o600,
            kind="redisRelayUsernameWriteFailed",
        )
        relay = _table(document, "redis_relay", self._config_path)
        password_configured = True
        settings = RedisRelaySettings(
            enabled=_required_bool(relay, "enabled", self._config_path),
            target_url=parsed.canonical_url,
            target_tls=parsed.tls,
            scope=_required_string(relay, "scope", self._config_path),
            include_recorder_network_context=_required_bool(
                relay, "include_recorder_network_context", self._config_path
            ),
            interval_seconds=_required_number(
                relay, "interval_seconds", self._config_path
            ),
            scan_count=_required_int(relay, "scan_count", self._config_path),
        )
        self._atomic_write(
            self._config_path,
            _toml(
                settings,
                username_configured=True,
                password_configured=password_configured,
            ),
            mode=0o600,
        )

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

    def _configured_secret(
        self,
        configured_path: object,
        *,
        expected_contract: str,
        path: Path,
        missing_kind: str,
        read_kind: str,
        invalid_kind: str,
        field: str,
    ) -> bool:
        if configured_path is None:
            return False
        if not isinstance(configured_path, str):
            raise _invalid(f"{field} must be a string", self._config_path)
        if not configured_path.strip():
            raise _invalid(f"{field} must not be empty", self._config_path)
        if configured_path != expected_contract:
            raise _invalid(
                f"{field} is not the Runtime secret contract",
                self._config_path,
            )
        try:
            secret = path.read_text(encoding="utf-8")
        except FileNotFoundError as error:
            raise GuestControlDependencyError(
                f"redis relay {field} is configured but missing: {path}",
                kind=missing_kind,
            ) from error
        except UnicodeDecodeError as error:
            raise GuestControlDependencyError(
                f"redis relay {field} is not valid UTF-8: {path}",
                kind=invalid_kind,
            ) from error
        except OSError as error:
            raise GuestControlDependencyError(
                f"redis relay {field} read failed path={path}: {error}",
                kind=read_kind,
            ) from error
        if credential_text_without_one_trailing_newline(secret) == "":
            raise GuestControlDependencyError(
                f"redis relay {field} file is empty: {path}",
                kind=invalid_kind,
            )
        return True

    def _atomic_write(
        self,
        path: Path,
        content: str,
        *,
        mode: int,
        kind: str = "redisRelaySettingsWriteFailed",
    ) -> None:
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
                with suppress(FileNotFoundError):
                    os.unlink(temporary)
            raise GuestControlDependencyError(
                f"redis relay settings write failed path={path}: {error}",
                kind=kind,
            ) from error

    def _remove_secret(self, path: Path, *, kind: str) -> None:
        try:
            path.unlink(missing_ok=True)
        except OSError as error:
            raise GuestControlDependencyError(
                f"redis relay secret removal failed path={path}: {error}",
                kind=kind,
            ) from error


def _toml(
    settings: RedisRelaySettings,
    *,
    username_configured: bool,
    password_configured: bool,
) -> str:
    lines = [
        "[redis_relay]",
        f"enabled = {str(settings.enabled).lower()}",
        f'scope = "{settings.scope}"',
        "include_recorder_network_context = "
        f"{str(settings.include_recorder_network_context).lower()}",
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
    if username_configured:
        lines.append(f'username_file = "{TARGET_USERNAME_FILE_CONTRACT}"')
    if password_configured:
        lines.append(f'password_file = "{TARGET_PASSWORD_FILE_CONTRACT}"')
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
    numeric = float(value)
    if not math.isfinite(numeric):
        raise _invalid(f"{name} must be a finite number", path)
    return numeric


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
