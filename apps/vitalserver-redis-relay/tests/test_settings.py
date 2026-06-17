from pathlib import Path

import pytest

from vitalserver_redis_relay.key_filter import RelayScope
from vitalserver_redis_relay.settings import (
    RelaySettingsError,
    disabled_settings,
    parse_settings,
)


def test_missing_config_means_disabled_settings() -> None:
    settings = disabled_settings()

    assert settings.enabled is False
    assert settings.source.host == "redis"
    assert settings.target is None


def test_parse_enabled_settings_reads_password_file(tmp_path: Path) -> None:
    password = tmp_path / "target-password"
    password.write_text("secret\n")

    settings = parse_settings(
        {
            "redis_relay": {
                "enabled": True,
                "scope": "vital_reconstruction",
                "include_recorder_network_context": True,
            },
            "target": {
                "host": "10.0.0.12",
                "port": 6380,
                "database": 2,
                "username": "default",
                "password_file": str(password),
                "tls": True,
            },
        },
        base_dir=tmp_path,
    )

    assert settings.enabled is True
    assert settings.scope == RelayScope.VITAL_RECONSTRUCTION
    assert settings.include_recorder_network_context is True
    assert settings.target is not None
    assert settings.target.password == "secret"
    assert settings.target.tls is True


def test_enabled_settings_require_target_host(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match=r"target\.host is required"):
        parse_settings({"redis_relay": {"enabled": True}}, base_dir=tmp_path)


def test_password_file_failure_is_explicit(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.password_file read failed",
    ):
        parse_settings(
            {
                "redis_relay": {"enabled": True},
                "target": {
                    "host": "10.0.0.12",
                    "password_file": str(tmp_path / "missing"),
                },
            },
            base_dir=tmp_path,
        )
