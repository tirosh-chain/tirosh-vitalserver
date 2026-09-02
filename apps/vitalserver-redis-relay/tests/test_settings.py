from __future__ import annotations

import math
import os
from pathlib import Path
from typing import Any

import pytest

from vitalserver_redis_relay.key_filter import RelayScope
from vitalserver_redis_relay.settings import (
    RelaySettingsError,
    load_settings,
    parse_settings,
)

SENTINEL_USERNAME = "relay-user"
SENTINEL_PASSWORD = "sentinel-password"


def enabled_config(**overrides: object) -> dict[str, Any]:
    document: dict[str, Any] = {
        "redis_relay": {"enabled": True},
        "source": {"host": "redis"},
        "target": {"url": "redis://10.0.0.12:6379/0"},
    }
    document.update(overrides)
    return document


def write_secret(path: Path, content: str | bytes) -> Path:
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content)
    return path


def test_missing_config_is_not_disabled(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match="relay config file is missing"):
        load_settings(tmp_path / "missing.toml")


def test_invalid_toml_is_config_invalid(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    config.write_text("not toml = [")
    with pytest.raises(RelaySettingsError, match="invalid TOML"):
        load_settings(config)


def test_enabled_key_is_required(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"redis_relay\.enabled is required",
    ):
        parse_settings({"redis_relay": {}}, base_dir=tmp_path)


def test_explicit_enabled_false_is_disabled(tmp_path: Path) -> None:
    settings = parse_settings(
        {"redis_relay": {"enabled": False}},
        base_dir=tmp_path,
    )

    assert settings.enabled is False
    assert settings.source is None
    assert settings.target is None


def test_disabled_does_not_read_credential_files(tmp_path: Path) -> None:
    settings = parse_settings(
        {
            "redis_relay": {"enabled": False},
            "source": {
                "host": "redis",
                "password_file": str(tmp_path / "missing-source"),
            },
            "target": {
                "url": "redis://10.0.0.12:6379/0",
                "password_file": str(tmp_path / "missing-target"),
            },
        },
        base_dir=tmp_path,
    )

    assert settings.enabled is False
    assert settings.source is None
    assert settings.target is None


def test_enabled_requires_source_table_and_host(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match="source table is required"):
        parse_settings(
            {
                "redis_relay": {"enabled": True},
                "target": {"url": "redis://10.0.0.12:6379/0"},
            },
            base_dir=tmp_path,
        )
    with pytest.raises(RelaySettingsError, match=r"source\.host is required"):
        parse_settings(enabled_config(source={}), base_dir=tmp_path)
    with pytest.raises(
        RelaySettingsError,
        match=r"source\.host must not be empty",
    ):
        parse_settings(enabled_config(source={"host": "  "}), base_dir=tmp_path)


def test_parse_enabled_settings_reads_password_file(tmp_path: Path) -> None:
    password = write_secret(tmp_path / "target-password", f"{SENTINEL_PASSWORD}\n")

    settings = parse_settings(
        enabled_config(
            redis_relay={
                "enabled": True,
                "scope": "vital_reconstruction",
                "include_recorder_network_context": True,
            },
            source={"host": "redis"},
            target={
                "url": "rediss://10.0.0.12:6380/2",
                "password_file": str(password),
            },
        ),
        base_dir=tmp_path,
    )

    assert settings.enabled is True
    assert settings.scope == RelayScope.VITAL_RECONSTRUCTION
    assert settings.include_recorder_network_context is True
    assert settings.source is not None
    assert settings.source.host == "redis"
    assert settings.source.password is None
    assert settings.target is not None
    assert settings.target.host == "10.0.0.12"
    assert settings.target.port == 6380
    assert settings.target.database == 2
    assert settings.target.username is None
    assert settings.target.password == SENTINEL_PASSWORD
    assert settings.target.tls is True
    assert settings.publish_contract.event_stream_key == "vitalserver:relay:events"
    assert settings.publish_contract.target_key_prefix == "vitalserver:"
    assert SENTINEL_PASSWORD not in repr(settings)
    assert SENTINEL_PASSWORD not in repr(settings.target)


def test_parse_enabled_settings_reads_publish_contract(tmp_path: Path) -> None:
    settings = parse_settings(
        enabled_config(
            publish={
                "target_key_prefix": "mirror:",
                "event_stream_key": "mirror:events",
                "fingerprint_hash_key": "mirror:fingerprints",
                "publish_dedupe_hash_key": "mirror:published",
                "event_stream_maxlen": 5000,
                "publisher_id": "helper-a",
            },
        ),
        base_dir=tmp_path,
    )

    assert settings.publish_contract.target_key_prefix == "mirror:"
    assert settings.publish_contract.event_stream_key == "mirror:events"
    assert settings.publish_contract.fingerprint_hash_key == "mirror:fingerprints"
    assert settings.publish_contract.publish_dedupe_hash_key == "mirror:published"
    assert settings.publish_contract.event_stream_maxlen == 5000
    assert settings.publish_contract.publisher_id == "helper-a"


def test_enabled_settings_require_target_url(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match="target table is required"):
        parse_settings(
            {
                "redis_relay": {"enabled": True},
                "source": {"host": "redis"},
            },
            base_dir=tmp_path,
        )
    with pytest.raises(RelaySettingsError, match=r"target\.url is required"):
        parse_settings(
            {
                "redis_relay": {"enabled": True},
                "source": {"host": "redis"},
                "target": {},
            },
            base_dir=tmp_path,
        )


def test_enabled_settings_reject_invalid_target_url(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match=r"target\.url scheme"):
        parse_settings(
            enabled_config(target={"url": "http://10.0.0.12:6379/0"}),
            base_dir=tmp_path,
        )


def test_source_password_file_success_and_failures(tmp_path: Path) -> None:
    password = write_secret(tmp_path / "source-password", f"{SENTINEL_PASSWORD}\n")
    settings = parse_settings(
        enabled_config(
            source={"host": "127.0.0.1", "password_file": str(password)},
        ),
        base_dir=tmp_path,
    )
    assert settings.source is not None
    assert settings.source.password == SENTINEL_PASSWORD
    assert settings.source.username is None
    assert SENTINEL_PASSWORD not in repr(settings.source)

    with pytest.raises(
        RelaySettingsError,
        match=r"source\.password_file is missing",
    ):
        parse_settings(
            enabled_config(
                source={
                    "host": "127.0.0.1",
                    "password_file": str(tmp_path / "missing"),
                },
            ),
            base_dir=tmp_path,
        )

    empty = write_secret(tmp_path / "empty-source", "\n")
    with pytest.raises(
        RelaySettingsError,
        match=r"source\.password_file is empty",
    ):
        parse_settings(
            enabled_config(
                source={"host": "127.0.0.1", "password_file": str(empty)},
            ),
            base_dir=tmp_path,
        )

    invalid_utf8 = write_secret(tmp_path / "bad-source", b"\xff")
    with pytest.raises(
        RelaySettingsError,
        match=r"source\.password_file is not valid UTF-8",
    ):
        parse_settings(
            enabled_config(
                source={"host": "127.0.0.1", "password_file": str(invalid_utf8)},
            ),
            base_dir=tmp_path,
        )


def test_source_password_file_permission_failure_is_explicit(tmp_path: Path) -> None:
    password = write_secret(tmp_path / "source-password", f"{SENTINEL_PASSWORD}\n")
    password.chmod(0)
    try:
        if os.access(password, os.R_OK):
            pytest.skip("process can read mode 0 files")
        with pytest.raises(
            RelaySettingsError,
            match=r"source\.password_file read failed",
        ):
            parse_settings(
                enabled_config(
                    source={"host": "127.0.0.1", "password_file": str(password)},
                ),
                base_dir=tmp_path,
            )
    finally:
        password.chmod(0o600)


def test_target_username_and_password_files(tmp_path: Path) -> None:
    username = write_secret(tmp_path / "username", f"{SENTINEL_USERNAME}\n")
    password = write_secret(tmp_path / "password", f"{SENTINEL_PASSWORD}\r\n")
    settings = parse_settings(
        enabled_config(
            target={
                "url": "rediss://10.0.0.12:6380/2",
                "username_file": str(username),
                "password_file": str(password),
            },
        ),
        base_dir=tmp_path,
    )

    assert settings.target is not None
    assert settings.target.username == SENTINEL_USERNAME
    assert settings.target.password == SENTINEL_PASSWORD
    assert settings.target.tls is True
    assert SENTINEL_USERNAME not in repr(settings)
    assert SENTINEL_PASSWORD not in repr(settings)


def test_secret_file_keeps_interior_whitespace_and_one_trailing_newline(
    tmp_path: Path,
) -> None:
    password = write_secret(tmp_path / "password", b" lead\ntrail\n\n")
    settings = parse_settings(
        enabled_config(
            target={
                "url": "redis://10.0.0.12:6379/0",
                "password_file": str(password),
            },
        ),
        base_dir=tmp_path,
    )

    assert settings.target is not None
    assert settings.target.password == " lead\ntrail\n"


def test_target_url_password_is_rejected_without_echoing_secret(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.url must not contain a password",
    ) as error:
        parse_settings(
            enabled_config(
                target={
                    "url": (
                        f"redis://{SENTINEL_USERNAME}:{SENTINEL_PASSWORD}"
                        "@10.0.0.12:6379/0"
                    ),
                },
            ),
            base_dir=tmp_path,
        )

    message = str(error.value)
    assert SENTINEL_PASSWORD not in message
    assert SENTINEL_USERNAME not in message
    assert "10.0.0.12" not in message


def test_url_username_is_rejected_without_echoing_secret(tmp_path: Path) -> None:
    password = write_secret(tmp_path / "password", f"{SENTINEL_PASSWORD}\n")
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.url must not contain a username",
    ) as error:
        parse_settings(
            enabled_config(
                target={
                    "url": f"redis://{SENTINEL_USERNAME}@10.0.0.12:6379/0",
                    "password_file": str(password),
                },
            ),
            base_dir=tmp_path,
        )

    assert SENTINEL_USERNAME not in str(error.value)
    assert SENTINEL_PASSWORD not in str(error.value)
    assert error.value.__cause__ is None


def test_empty_username_and_password_files_are_invalid(tmp_path: Path) -> None:
    empty_username = write_secret(tmp_path / "username", "")
    password = write_secret(tmp_path / "password", f"{SENTINEL_PASSWORD}\n")
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.username_file is empty",
    ):
        parse_settings(
            enabled_config(
                target={
                    "url": "redis://10.0.0.12:6379/0",
                    "username_file": str(empty_username),
                    "password_file": str(password),
                },
            ),
            base_dir=tmp_path,
        )

    username = write_secret(tmp_path / "user", f"{SENTINEL_USERNAME}\n")
    empty_password = write_secret(tmp_path / "empty-password", "")
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.password_file is empty",
    ):
        parse_settings(
            enabled_config(
                target={
                    "url": "redis://10.0.0.12:6379/0",
                    "username_file": str(username),
                    "password_file": str(empty_password),
                },
            ),
            base_dir=tmp_path,
        )


def test_username_without_password_is_rejected(tmp_path: Path) -> None:
    username = write_secret(tmp_path / "username", f"{SENTINEL_USERNAME}\n")
    with pytest.raises(
        RelaySettingsError,
        match=r"target username requires target\.password_file",
    ):
        parse_settings(
            enabled_config(
                target={
                    "url": "redis://10.0.0.12:6379/0",
                    "username_file": str(username),
                },
            ),
            base_dir=tmp_path,
        )


def test_url_username_without_password_is_rejected(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.url must not contain a username",
    ) as error:
        parse_settings(
            enabled_config(
                target={"url": f"redis://{SENTINEL_USERNAME}@10.0.0.12:6379/0"},
            ),
            base_dir=tmp_path,
        )

    assert SENTINEL_USERNAME not in str(error.value)
    assert error.value.__cause__ is None


def test_relative_password_file_uses_config_directory(tmp_path: Path) -> None:
    write_secret(tmp_path / "pw", f"{SENTINEL_PASSWORD}\n")
    settings = parse_settings(
        enabled_config(
            target={
                "url": "redis://10.0.0.12:6379/0",
                "password_file": "pw",
            },
        ),
        base_dir=tmp_path,
    )

    assert settings.target is not None
    assert settings.target.password == SENTINEL_PASSWORD


def test_password_file_failure_is_explicit(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match=r"target\.password_file is missing"):
        parse_settings(
            enabled_config(
                target={
                    "url": "redis://10.0.0.12:6379/0",
                    "password_file": str(tmp_path / "missing"),
                },
            ),
            base_dir=tmp_path,
        )


def test_publish_contract_rejects_empty_event_stream_key(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match="event_stream_key must not be empty"):
        parse_settings(
            enabled_config(publish={"event_stream_key": ""}),
            base_dir=tmp_path,
        )


def test_canonical_guest_control_toml_parses(tmp_path: Path) -> None:
    username = write_secret(
        tmp_path / "redis-relay-target-username",
        f"{SENTINEL_USERNAME}\n",
    )
    password = write_secret(
        tmp_path / "redis-relay-target-password",
        f"{SENTINEL_PASSWORD}\n",
    )
    config = tmp_path / "redis-relay.toml"
    config.write_text(
        "\n".join(
            [
                "[redis_relay]",
                "enabled = true",
                'scope = "vital_reconstruction"',
                "include_recorder_network_context = false",
                "interval_seconds = 1.0",
                "scan_count = 1000",
                "",
                "[source]",
                'host = "redis"',
                "port = 6379",
                "database = 0",
                "",
                "[target]",
                'url = "redis://example.test:6379/0"',
                f'username_file = "{username}"',
                f'password_file = "{password}"',
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
    )

    settings = load_settings(config)

    assert settings.enabled is True
    assert settings.source is not None
    assert settings.source.host == "redis"
    assert settings.target is not None
    assert settings.target.host == "example.test"
    assert settings.target.username == SENTINEL_USERNAME
    assert settings.target.password == SENTINEL_PASSWORD
    assert SENTINEL_PASSWORD not in repr(settings)
    assert SENTINEL_USERNAME not in repr(settings)


def test_explicit_empty_credential_paths_are_not_no_auth(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"source\.password_file must not be empty",
    ):
        parse_settings(
            enabled_config(source={"host": "redis", "password_file": ""}),
            base_dir=tmp_path,
        )
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.username_file must not be empty",
    ):
        parse_settings(
            enabled_config(
                target={
                    "url": "redis://10.0.0.12:6379/0",
                    "username_file": "   ",
                },
            ),
            base_dir=tmp_path,
        )
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.password_file must not be empty",
    ):
        parse_settings(
            enabled_config(
                target={
                    "url": "redis://10.0.0.12:6379/0",
                    "password_file": "",
                },
            ),
            base_dir=tmp_path,
        )


def test_absent_credential_paths_remain_unspecified(tmp_path: Path) -> None:
    settings = parse_settings(enabled_config(), base_dir=tmp_path)

    assert settings.source is not None
    assert settings.source.password is None
    assert settings.target is not None
    assert settings.target.username is None
    assert settings.target.password is None


def test_malformed_target_url_is_config_invalid(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match=r"target\.url is invalid") as error:
        parse_settings(
            enabled_config(target={"url": "redis://[broken"}),
            base_dir=tmp_path,
        )

    assert "broken" not in str(error.value)
    assert "redis://" not in str(error.value)
    assert error.value.__cause__ is None


def test_invalid_ipv6_and_port_target_urls_are_config_invalid(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.url is invalid",
    ) as ipv6_error:
        parse_settings(
            enabled_config(
                target={
                    "url": (f"redis://[{SENTINEL_USERNAME}:{SENTINEL_PASSWORD}"),
                },
            ),
            base_dir=tmp_path,
        )
    assert SENTINEL_USERNAME not in str(ipv6_error.value)
    assert SENTINEL_PASSWORD not in str(ipv6_error.value)
    assert ipv6_error.value.__cause__ is None

    with pytest.raises(
        RelaySettingsError,
        match=r"target\.url port is invalid",
    ) as port_error:
        parse_settings(
            enabled_config(target={"url": "redis://10.0.0.12:abc/0"}),
            base_dir=tmp_path,
        )
    assert "abc" not in str(port_error.value)
    assert "10.0.0.12" not in str(port_error.value)
    assert port_error.value.__cause__ is None


def test_invalid_scope_is_config_invalid(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"redis_relay\.scope is invalid",
    ) as error:
        parse_settings(
            enabled_config(redis_relay={"enabled": True, "scope": "invalid-scope"}),
            base_dir=tmp_path,
        )

    assert "invalid-scope" not in str(error.value)
    assert error.value.__cause__ is None


def test_boolean_is_not_accepted_as_numeric_setting(tmp_path: Path) -> None:
    with pytest.raises(RelaySettingsError, match="port must be an integer"):
        parse_settings(
            enabled_config(source={"host": "redis", "port": True}),
            base_dir=tmp_path,
        )
    with pytest.raises(RelaySettingsError, match="scan_count must be an integer"):
        parse_settings(
            enabled_config(redis_relay={"enabled": True, "scan_count": False}),
            base_dir=tmp_path,
        )
    with pytest.raises(RelaySettingsError, match="interval_seconds must be numeric"):
        parse_settings(
            enabled_config(
                redis_relay={"enabled": True, "interval_seconds": True},
            ),
            base_dir=tmp_path,
        )
    with pytest.raises(
        RelaySettingsError,
        match="event_stream_maxlen must be an integer",
    ):
        parse_settings(
            enabled_config(publish={"event_stream_maxlen": True}),
            base_dir=tmp_path,
        )


def test_explicit_target_url_port_zero_is_invalid(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.url port is invalid",
    ) as error:
        parse_settings(
            enabled_config(target={"url": "redis://target:0/0"}),
            base_dir=tmp_path,
        )

    assert "target:0" not in str(error.value)
    assert error.value.__cause__ is None


def test_empty_target_url_port_is_invalid(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"target\.url port is invalid",
    ) as error:
        parse_settings(
            enabled_config(target={"url": "redis://target:/0"}),
            base_dir=tmp_path,
        )

    assert "target:" not in str(error.value)
    assert error.value.__cause__ is None


def test_missing_target_url_port_defaults_to_6379(tmp_path: Path) -> None:
    settings = parse_settings(
        enabled_config(target={"url": "redis://target/0"}),
        base_dir=tmp_path,
    )

    assert settings.target is not None
    assert settings.target.port == 6379


def test_explicit_valid_target_url_port_is_kept(tmp_path: Path) -> None:
    settings = parse_settings(
        enabled_config(target={"url": "rediss://target:6380/2"}),
        base_dir=tmp_path,
    )

    assert settings.target is not None
    assert settings.target.port == 6380
    assert settings.target.tls is True
    assert settings.target.database == 2


def test_target_url_query_params_and_fragment_are_rejected(tmp_path: Path) -> None:
    cases = (
        (
            f"redis://10.0.0.12:6379/0?password={SENTINEL_PASSWORD}",
            r"target\.url must not contain a query",
        ),
        (
            "redis://10.0.0.12:6379/0;param",
            r"target\.url must not contain params",
        ),
        (
            f"redis://10.0.0.12:6379/0#{SENTINEL_USERNAME}",
            r"target\.url must not contain a fragment",
        ),
    )
    for url, match in cases:
        with pytest.raises(RelaySettingsError, match=match) as error:
            parse_settings(enabled_config(target={"url": url}), base_dir=tmp_path)
        assert SENTINEL_PASSWORD not in str(error.value)
        assert SENTINEL_USERNAME not in str(error.value)
        assert "10.0.0.12" not in str(error.value)
        assert error.value.__cause__ is None


def test_float_settings_reject_nan_and_inf(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match="interval_seconds must be a finite number",
    ):
        parse_settings(
            enabled_config(
                redis_relay={"enabled": True, "interval_seconds": math.nan},
            ),
            base_dir=tmp_path,
        )
    with pytest.raises(
        RelaySettingsError,
        match="status_interval_seconds must be a finite number",
    ):
        parse_settings(
            enabled_config(
                redis_relay={"enabled": True, "status_interval_seconds": math.inf},
            ),
            base_dir=tmp_path,
        )
    with pytest.raises(
        RelaySettingsError,
        match="interval_seconds must be a finite number",
    ):
        parse_settings(
            enabled_config(
                redis_relay={"enabled": True, "interval_seconds": -math.inf},
            ),
            base_dir=tmp_path,
        )


def test_secret_path_with_embedded_null_is_invalid(tmp_path: Path) -> None:
    with pytest.raises(
        RelaySettingsError,
        match=r"source\.password_file is invalid",
    ) as error:
        parse_settings(
            enabled_config(
                source={
                    "host": "redis",
                    "password_file": "secret" + chr(0) + "path",
                },
            ),
            base_dir=tmp_path,
        )

    assert "secret" not in str(error.value)
    assert error.value.__cause__ is None
