import math
import os
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.redis_relay_settings import (
    FileRedisRelaySettingsRepository,
)
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.redis_relay_settings import (
    RedisRelaySettingsContractError,
    parse_target_url,
    validated_redis_relay_settings,
)

SENTINEL_USERNAME = "relay-user"
SENTINEL_PASSWORD = "sentinel-password"


def initial_config(*, password: bool = False, legacy_username: bool = False) -> str:
    url = (
        f"redis://{SENTINEL_USERNAME}@example.test:6379/0"
        if legacy_username
        else "redis://example.test:6379/0"
    )
    password_line = (
        'password_file = "/run/tirosh/secrets/redis-relay-target-password"\n'
        if password
        else ""
    )
    return f"""[redis_relay]
enabled = false
scope = "vital_reconstruction"
include_recorder_network_context = false
interval_seconds = 1.0
scan_count = 1000

[source]
host = "redis"
port = 6379
database = 0

[target]
url = "{url}"
{password_line}
[publish]
target_key_prefix = "vitalserver:"
event_stream_key = "vitalserver:relay:events"
fingerprint_hash_key = "vitalserver:relay:fingerprints"
publish_dedupe_hash_key = "vitalserver:relay:published"
event_stream_maxlen = 100000
publisher_id = "vitalserver-helper-relay"
"""


def request(**overrides: object) -> dict[str, object]:
    document: dict[str, object] = {
        "enabled": True,
        "target": {
            "url": "redis://relay.example.test:6379/1",
            "username": "operator",
            "password": "new-secret",
            "clearPassword": False,
            "clearUsername": False,
            "tls": True,
        },
        "scope": "waveform_trend_only",
        "includeRecorderNetworkContext": True,
        "intervalSeconds": 0.5,
        "scanCount": 250,
    }
    document.update(overrides)
    return document


def repository(tmp_path: Path) -> FileRedisRelaySettingsRepository:
    return FileRedisRelaySettingsRepository(
        tmp_path / "redis-relay.toml",
        tmp_path / "redis-relay-target-username",
        tmp_path / "redis-relay-target-password",
    )


def read_target(document: dict[str, object]) -> dict[str, object]:
    target = document["target"]
    assert isinstance(target, dict)
    return target


def test_repository_reads_without_returning_secrets(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    config.write_text(initial_config(password=True))
    password.write_text("existing-secret")

    read = repository(tmp_path).read()

    assert read["target"] == {
        "url": "redis://example.test:6379/0",
        "usernameConfigured": False,
        "passwordConfigured": True,
        "tls": False,
    }
    assert "existing-secret" not in str(read)
    assert SENTINEL_USERNAME not in str(read)
    assert "username" not in read["target"]


def test_repository_applies_settings_and_preserves_secret_when_omitted(
    tmp_path: Path,
) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    config.write_text(initial_config(password=True))
    password.write_text("existing-secret")
    document = request()
    target = document["target"]
    assert isinstance(target, dict)
    target["password"] = ""

    repo = repository(tmp_path)
    repo.save(document)

    assert password.read_text() == "existing-secret"
    assert "password_file" in config.read_text()
    assert "username_file" in config.read_text()
    assert "operator@" not in config.read_text()
    read = repo.read()
    assert read["target"] == {
        "url": "rediss://relay.example.test:6379/1",
        "usernameConfigured": True,
        "passwordConfigured": True,
        "tls": True,
    }
    assert "operator" not in str(read)
    assert "new-secret" not in str(read)


def test_repository_replaces_and_clears_secrets(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    config.write_text(initial_config())
    repo = repository(tmp_path)

    repo.save(request())
    username = tmp_path / "redis-relay-target-username"
    password = tmp_path / "redis-relay-target-password"
    assert username.read_text() == "operator\n"
    assert password.read_text() == "new-secret\n"
    assert username.stat().st_mode & 0o777 == 0o600
    assert password.stat().st_mode & 0o777 == 0o600
    assert read_target(repo.read())["usernameConfigured"] is True
    assert read_target(repo.read())["passwordConfigured"] is True
    assert "operator" not in config.read_text()

    clear = request()
    clear_target = clear["target"]
    assert isinstance(clear_target, dict)
    clear_target["username"] = ""
    clear_target["password"] = ""
    clear_target["clearUsername"] = True
    clear_target["clearPassword"] = True
    repo.save(clear)
    assert not username.exists()
    assert not password.exists()
    assert read_target(repo.read())["usernameConfigured"] is False
    assert read_target(repo.read())["passwordConfigured"] is False


def test_repository_rejects_username_without_password(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    config.write_text(initial_config())
    document = request()
    target = document["target"]
    assert isinstance(target, dict)
    target["password"] = ""
    with pytest.raises(GuestControlDependencyError, match="username requires password"):
        repository(tmp_path).save(document)
    assert not (tmp_path / "redis-relay-target-username").exists()


def test_read_does_not_migrate_legacy_url_username(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    username = tmp_path / "redis-relay-target-username"
    original = initial_config(password=True, legacy_username=True)
    config.write_text(original)
    password.write_text("existing-secret\n")

    with pytest.raises(
        GuestControlDependencyError,
        match="requires migration",
    ) as error:
        repository(tmp_path).read()

    assert config.read_text() == original
    assert not username.exists()
    assert SENTINEL_USERNAME not in str(error.value)


def test_save_migrates_legacy_url_username(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    username = tmp_path / "redis-relay-target-username"
    config.write_text(initial_config(password=True, legacy_username=True))
    password.write_text("existing-secret\n")
    document = request()
    target = document["target"]
    assert isinstance(target, dict)
    target["password"] = ""

    repository(tmp_path).save(document)

    assert SENTINEL_USERNAME not in config.read_text()
    assert "username_file" in config.read_text()
    assert username.read_text() == "operator\n"
    assert password.read_text() == "existing-secret\n"
    assert SENTINEL_USERNAME not in username.read_text()


def test_migrate_legacy_url_username_is_idempotent(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    username = tmp_path / "redis-relay-target-username"
    config.write_text(initial_config(password=True, legacy_username=True))
    password.write_text("existing-secret\n")
    repo = repository(tmp_path)

    repo.migrate_legacy_target_credentials()
    first = config.read_text()
    assert SENTINEL_USERNAME not in first
    assert "username_file" in first
    assert username.read_text() == f"{SENTINEL_USERNAME}\n"
    assert "existing-secret" not in first

    repo.migrate_legacy_target_credentials()
    assert config.read_text() == first
    read = repo.read()
    target = read_target(read)
    assert target["url"] == "redis://example.test:6379/0"
    assert target["usernameConfigured"] is True
    assert SENTINEL_USERNAME not in str(read)


def test_migrate_rejects_url_password(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    config.write_text(
        initial_config().replace(
            "redis://example.test:6379/0",
            f"redis://user:{SENTINEL_PASSWORD}@example.test:6379/0",
        )
    )
    with pytest.raises(
        GuestControlDependencyError,
        match="must not contain a password",
    ) as error:
        repository(tmp_path).migrate_legacy_target_credentials()
    assert SENTINEL_PASSWORD not in str(error.value)


def test_migrate_rejects_username_without_password_file(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    config.write_text(initial_config(legacy_username=True))
    with pytest.raises(
        GuestControlDependencyError,
        match="username requires password_file",
    ):
        repository(tmp_path).migrate_legacy_target_credentials()


def test_repository_preserves_missing_and_invalid_state(tmp_path: Path) -> None:
    repo = repository(tmp_path)
    with pytest.raises(GuestControlDependencyError, match="is missing"):
        repo.read()
    config = tmp_path / "redis-relay.toml"
    config.write_text("not toml = [")
    with pytest.raises(GuestControlDependencyError, match="are invalid"):
        repo.read()
    config.write_text(initial_config(password=True))
    with pytest.raises(GuestControlDependencyError, match="configured but missing"):
        repo.read()


def test_contract_rejects_url_userinfo_and_ambiguous_settings() -> None:
    ambiguous = request()
    target = ambiguous["target"]
    assert isinstance(target, dict)
    target["clearPassword"] = True
    with pytest.raises(RedisRelaySettingsContractError, match="mutually exclusive"):
        validated_redis_relay_settings(ambiguous)
    with pytest.raises(RedisRelaySettingsContractError, match="scope is invalid"):
        validated_redis_relay_settings(request(scope="everything"))
    with pytest.raises(
        RedisRelaySettingsContractError,
        match="must not contain user-info",
    ) as error:
        validated_redis_relay_settings(
            request(
                target={
                    "url": f"redis://{SENTINEL_USERNAME}@host:6379/0",
                    "username": "",
                    "password": "",
                    "clearPassword": False,
                    "clearUsername": False,
                    "tls": False,
                }
            )
        )
    assert SENTINEL_USERNAME not in str(error.value)


def test_migrate_rejects_username_file_and_url_username(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    config.write_text(
        initial_config(password=True, legacy_username=True).replace(
            "[target]\n",
            (
                "[target]\n"
                'username_file = "/run/tirosh/secrets/redis-relay-target-username"\n'
            ),
        )
    )
    (tmp_path / "redis-relay-target-password").write_text("existing-secret\n")
    with pytest.raises(
        GuestControlDependencyError,
        match="cannot both be set",
    ) as error:
        repository(tmp_path).migrate_legacy_target_credentials()
    assert SENTINEL_USERNAME not in str(error.value)


def test_empty_username_file_path_is_invalid(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    config.write_text(
        initial_config().replace(
            "[target]\n",
            '[target]\nusername_file = ""\n',
        )
    )
    with pytest.raises(GuestControlDependencyError, match="must not be empty"):
        repository(tmp_path).read()


def test_username_file_utf8_failure_is_explicit(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    username = tmp_path / "redis-relay-target-username"
    password = tmp_path / "redis-relay-target-password"
    config.write_text(
        initial_config(password=True).replace(
            "[target]\n",
            (
                "[target]\n"
                'username_file = "/run/tirosh/secrets/redis-relay-target-username"\n'
            ),
        )
    )
    username.write_bytes(b"\xff\xfe")
    password.write_text("existing-secret\n")
    with pytest.raises(GuestControlDependencyError, match="not valid UTF-8"):
        repository(tmp_path).read()
    assert SENTINEL_USERNAME not in config.read_text()


def test_migrate_rejects_missing_password_file_before_write(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    username = tmp_path / "redis-relay-target-username"
    original = initial_config(password=True, legacy_username=True)
    config.write_text(original)
    with pytest.raises(
        GuestControlDependencyError,
        match="configured but missing",
    ):
        repository(tmp_path).migrate_legacy_target_credentials()
    assert config.read_text() == original
    assert not username.exists()


def test_migrate_rejects_unreadable_password_file_before_write(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    username = tmp_path / "redis-relay-target-username"
    original = initial_config(password=True, legacy_username=True)
    config.write_text(original)
    password.write_text("existing-secret\n")
    password.chmod(0)
    try:
        if os.access(password, os.R_OK):
            pytest.skip("process can read mode 0 files")
        with pytest.raises(GuestControlDependencyError, match="read failed"):
            repository(tmp_path).migrate_legacy_target_credentials()
        assert config.read_text() == original
        assert not username.exists()
    finally:
        password.chmod(0o600)


def test_migrate_rejects_invalid_utf8_password_file_before_write(
    tmp_path: Path,
) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    username = tmp_path / "redis-relay-target-username"
    original = initial_config(password=True, legacy_username=True)
    config.write_text(original)
    password.write_bytes(b"\xff\xfe")
    with pytest.raises(GuestControlDependencyError, match="not valid UTF-8") as error:
        repository(tmp_path).migrate_legacy_target_credentials()
    assert config.read_text() == original
    assert not username.exists()
    assert SENTINEL_USERNAME not in str(error.value)
    assert SENTINEL_PASSWORD not in str(error.value)


@pytest.mark.parametrize("content", [b"", b"\n", b"\r\n"])
def test_migrate_rejects_empty_password_file_before_write(
    tmp_path: Path,
    content: bytes,
) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    username = tmp_path / "redis-relay-target-username"
    original = initial_config(password=True, legacy_username=True)
    config.write_text(original)
    password.write_bytes(content)
    with pytest.raises(GuestControlDependencyError, match="file is empty") as error:
        repository(tmp_path).migrate_legacy_target_credentials()
    assert config.read_text() == original
    assert not username.exists()
    assert SENTINEL_USERNAME not in str(error.value)


def test_migrate_rejects_password_file_outside_contract_path(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    username = tmp_path / "redis-relay-target-username"
    original = initial_config(legacy_username=True).replace(
        "[target]\n",
        ('[target]\npassword_file = "/tmp/redis-relay-target-password"\n'),
    )
    config.write_text(original)
    (tmp_path / "redis-relay-target-password").write_text("existing-secret\n")
    with pytest.raises(
        GuestControlDependencyError,
        match="is not the Runtime secret contract",
    ):
        repository(tmp_path).migrate_legacy_target_credentials()
    assert config.read_text() == original
    assert not username.exists()


def test_read_rejects_secret_path_with_same_basename_outside_contract(
    tmp_path: Path,
) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    config.write_text(
        initial_config(password=True).replace(
            "[target]\n",
            ('[target]\nusername_file = "/tmp/redis-relay-target-username"\n'),
        )
    )
    (tmp_path / "redis-relay-target-username").write_text("operator\n")
    password.write_text("existing-secret\n")
    with pytest.raises(
        GuestControlDependencyError,
        match="is not the Runtime secret contract",
    ):
        repository(tmp_path).read()


def test_password_file_crlf_only_is_empty(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    config.write_text(initial_config(password=True))
    password.write_bytes(b"\r\n")
    with pytest.raises(GuestControlDependencyError, match="file is empty"):
        repository(tmp_path).read()


def test_password_file_double_newline_is_configured(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    config.write_text(initial_config(password=True))
    password.write_bytes(b"\n\n")
    read = repository(tmp_path).read()
    assert read_target(read)["passwordConfigured"] is True
    assert "\n\n" not in str(read)


def test_parse_target_url_rejects_empty_port_query_params_and_fragment() -> None:
    cases = (
        ("redis://example.test:/0", "port is invalid"),
        ("redis://example.test:0/0", "port is invalid"),
        ("redis://example.test:65536/0", "port is invalid"),
        (
            f"redis://example.test:6379/0?password={SENTINEL_PASSWORD}",
            "must not contain a query",
        ),
        ("redis://example.test:6379/0;param", "must not contain params"),
        (
            f"redis://example.test:6379/0#{SENTINEL_USERNAME}",
            "must not contain a fragment",
        ),
    )
    for url, match in cases:
        with pytest.raises(RedisRelaySettingsContractError, match=match) as error:
            parse_target_url(url, tls=False)
        assert SENTINEL_PASSWORD not in str(error.value)
        assert SENTINEL_USERNAME not in str(error.value)
        assert "example.test" not in str(error.value)


def test_interval_seconds_rejects_nan_and_inf() -> None:
    for value in (math.nan, math.inf, -math.inf):
        document = request()
        document["intervalSeconds"] = value
        with pytest.raises(
            RedisRelaySettingsContractError,
            match="finite number",
        ):
            validated_redis_relay_settings(document)
