from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_guest_tools.domain.redis_relay_settings import (
    RedisRelaySettingsContractError,
    parse_target_url,
    validated_redis_relay_settings,
)
from vitalserver_redis_relay.settings import RelaySettingsError, parse_settings

SENTINEL_USERNAME = "relay-user"
SENTINEL_PASSWORD = "sentinel-password"

ACCEPTED = (
    ("redis://example.test:6379/0", "example.test", 6379, 0, False),
    ("rediss://example.test:6380/2", "example.test", 6380, 2, True),
    ("redis://example.test/0", "example.test", 6379, 0, False),
)

REJECTED = (
    ("redis://example.test:/0", "port is invalid"),
    ("redis://example.test:0/0", "port is invalid"),
    ("redis://example.test:65536/0", "port is invalid"),
    (f"redis://example.test:6379/0?password={SENTINEL_PASSWORD}", "query"),
    ("redis://example.test:6379/0;param", "params"),
    (f"redis://example.test:6379/0#{SENTINEL_USERNAME}", "fragment"),
    (
        f"redis://user:{SENTINEL_PASSWORD}@example.test:6379/0",
        "password",
    ),
)


def test_producer_accepted_urls_are_consumed_identically_by_relay(
    tmp_path: Path,
) -> None:
    for url, host, port, database, tls in ACCEPTED:
        parsed = parse_target_url(url, tls=tls)
        assert parsed.legacy_username is None
        settings = parse_settings(
            {
                "redis_relay": {"enabled": True},
                "source": {"host": "redis"},
                "target": {"url": parsed.canonical_url},
            },
            base_dir=tmp_path,
        )
        assert settings.target is not None
        assert settings.target.host == host
        assert settings.target.port == port
        assert settings.target.database == database
        assert settings.target.tls is tls


def test_producer_rejected_urls_are_not_normalized_by_either_parser(
    tmp_path: Path,
) -> None:
    for url, match in REJECTED:
        with pytest.raises(RedisRelaySettingsContractError, match=match) as guest:
            parse_target_url(url, tls=url.startswith("rediss://"))
        with pytest.raises(RelaySettingsError, match=match) as relay:
            parse_settings(
                {
                    "redis_relay": {"enabled": True},
                    "source": {"host": "redis"},
                    "target": {"url": url},
                },
                base_dir=tmp_path,
            )
        for error in (guest.value, relay.value):
            assert SENTINEL_USERNAME not in str(error)
            assert SENTINEL_PASSWORD not in str(error)
            assert "example.test" not in str(error)


def test_url_username_is_not_consumed_as_canonical_target(tmp_path: Path) -> None:
    url = f"redis://{SENTINEL_USERNAME}@example.test:6379/0"
    parsed = parse_target_url(url, tls=False)
    assert parsed.legacy_username == SENTINEL_USERNAME
    assert parsed.canonical_url == "redis://example.test:6379/0"
    with pytest.raises(RelaySettingsError, match="username") as relay:
        parse_settings(
            {
                "redis_relay": {"enabled": True},
                "source": {"host": "redis"},
                "target": {"url": url},
            },
            base_dir=tmp_path,
        )
    with pytest.raises(RedisRelaySettingsContractError, match="user-info") as guest:
        validated_redis_relay_settings(
            {
                "enabled": False,
                "target": {
                    "url": url,
                    "username": "",
                    "password": "",
                    "clearPassword": False,
                    "clearUsername": False,
                    "tls": False,
                },
                "scope": "vital_reconstruction",
                "includeRecorderNetworkContext": False,
                "intervalSeconds": 1.0,
                "scanCount": 1000,
            }
        )
    assert SENTINEL_USERNAME not in str(relay.value)
    assert SENTINEL_USERNAME not in str(guest.value)
