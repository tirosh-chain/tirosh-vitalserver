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
                "url": "rediss://default@10.0.0.12:6380/2",
                "password_file": str(password),
            },
        },
        base_dir=tmp_path,
    )

    assert settings.enabled is True
    assert settings.scope == RelayScope.VITAL_RECONSTRUCTION
    assert settings.include_recorder_network_context is True
    assert settings.target is not None
    assert settings.target.host == "10.0.0.12"
    assert settings.target.port == 6380
    assert settings.target.database == 2
    assert settings.target.username == "default"
    assert settings.target.password == "secret"
    assert settings.target.tls is True


def test_enabled_settings_require_target_url(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match=r"target\.url is required"):
        parse_settings({"redis_relay": {"enabled": True}}, base_dir=tmp_path)


def test_enabled_settings_reject_invalid_target_url(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match=r"target\.url scheme"):
        parse_settings(
            {
                "redis_relay": {"enabled": True},
                "target": {"url": "http://10.0.0.12:6379/0"},
            },
            base_dir=tmp_path,
        )


def test_password_file_failure_is_explicit(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.password_file read failed",
    ):
        parse_settings(
            {
                "redis_relay": {"enabled": True},
                "target": {
                    "url": "redis://10.0.0.12:6379/0",
                    "password_file": str(tmp_path / "missing"),
                },
            },
            base_dir=tmp_path,
        )
