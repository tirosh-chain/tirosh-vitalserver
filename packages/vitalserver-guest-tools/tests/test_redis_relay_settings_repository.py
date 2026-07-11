from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.redis_relay_settings import (
    FileRedisRelaySettingsRepository,
)
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.redis_relay_settings import (
    RedisRelaySettingsContractError,
    validated_redis_relay_settings,
)


def initial_config(*, password: bool = False) -> str:
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
url = "redis://relay@example.test:6379/0"
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
            "tls": True,
        },
        "scope": "waveform_trend_only",
        "includeRecorderNetworkContext": True,
        "intervalSeconds": 0.5,
        "scanCount": 250,
    }
    document.update(overrides)
    return document


def test_repository_reads_without_returning_password(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    config.write_text(initial_config(password=True))
    password.write_text("existing-secret")

    read = FileRedisRelaySettingsRepository(config, password).read()

    assert read["target"] == {
        "url": "redis://relay@example.test:6379/0",
        "username": "relay",
        "passwordConfigured": True,
        "tls": False,
    }
    assert "existing-secret" not in str(read)


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

    repository = FileRedisRelaySettingsRepository(config, password)
    repository.save(document)

    assert password.read_text() == "existing-secret"
    assert "password_file" in config.read_text()
    read = repository.read()
    assert read["target"] == {
        "url": "rediss://operator@relay.example.test:6379/1",
        "username": "operator",
        "passwordConfigured": True,
        "tls": True,
    }


def test_repository_replaces_and_clears_secret(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    password = tmp_path / "redis-relay-target-password"
    config.write_text(initial_config())
    repository = FileRedisRelaySettingsRepository(config, password)

    repository.save(request())
    assert password.read_text() == "new-secret\n"
    assert repository.read()["target"]["passwordConfigured"] is True

    clear = request()
    clear_target = clear["target"]
    assert isinstance(clear_target, dict)
    clear_target["password"] = ""
    clear_target["clearPassword"] = True
    repository.save(clear)
    assert not password.exists()
    assert repository.read()["target"]["passwordConfigured"] is False


def test_repository_preserves_missing_invalid_and_missing_secret(tmp_path: Path) -> None:
    config = tmp_path / "redis-relay.toml"
    repository = FileRedisRelaySettingsRepository(
        config, tmp_path / "redis-relay-target-password"
    )
    with pytest.raises(GuestControlDependencyError, match="is missing"):
        repository.read()
    config.write_text("not toml = [")
    with pytest.raises(GuestControlDependencyError, match="are invalid"):
        repository.read()
    config.write_text(initial_config(password=True))
    with pytest.raises(GuestControlDependencyError, match="configured but missing"):
        repository.read()


def test_contract_rejects_ambiguous_or_invalid_settings() -> None:
    ambiguous = request()
    target = ambiguous["target"]
    assert isinstance(target, dict)
    target["clearPassword"] = True
    with pytest.raises(RedisRelaySettingsContractError, match="mutually exclusive"):
        validated_redis_relay_settings(ambiguous)
    with pytest.raises(RedisRelaySettingsContractError, match="scope is invalid"):
        validated_redis_relay_settings(request(scope="everything"))
