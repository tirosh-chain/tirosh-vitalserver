from __future__ import annotations

from typing import Any

import pytest

from vitaldb_observer.redis_client import RedisClient, RedisProtocolError


class FakeRedisClient(RedisClient):
    response_mode = "valid"

    def __init__(self) -> None:
        self.commands: list[tuple[str, ...]] = []

    def command(self, *parts: str) -> Any:
        self.commands.append(parts)
        if self.response_mode == "wrong-type":
            return "wrong-type"
        if parts[0] == "LRANGE":
            if self.response_mode == "non-string-item":
                return ["a", 1]
            return ["a", "b"]
        if self.response_mode == "malformed-scan":
            return ["7"]
        if self.response_mode == "scan-non-string-key":
            return ["0", ["ip_A", 1]]
        cursor = parts[1]
        if cursor == "0":
            return ["7", ["ip_A", "ip_B"]]
        return ["0", ["ip_B", "ip_C"]]


def test_scan_collects_unique_keys_without_keys_command() -> None:
    client = FakeRedisClient()

    assert client.scan("ip_*", count=2) == ["ip_A", "ip_B", "ip_C"]
    assert client.commands == [
        ("SCAN", "0", "MATCH", "ip_*", "COUNT", "2"),
        ("SCAN", "7", "MATCH", "ip_*", "COUNT", "2"),
    ]


def test_lrange_returns_string_values() -> None:
    client = FakeRedisClient()

    assert client.lrange("events", -2, -1) == ["a", "b"]
    assert client.commands == [("LRANGE", "events", "-2", "-1")]


def test_lrange_rejects_non_list_response() -> None:
    client = FakeRedisClient()
    client.response_mode = "wrong-type"

    with pytest.raises(RedisProtocolError, match="unexpected LRANGE response"):
        client.lrange("events", -2, -1)


def test_lrange_rejects_non_string_items() -> None:
    client = FakeRedisClient()
    client.response_mode = "non-string-item"

    with pytest.raises(RedisProtocolError, match="unexpected LRANGE item"):
        client.lrange("events", -2, -1)


def test_smembers_rejects_non_list_response() -> None:
    client = FakeRedisClient()
    client.response_mode = "wrong-type"

    with pytest.raises(RedisProtocolError, match="unexpected SMEMBERS response"):
        client.smembers("vrs")


def test_scan_rejects_malformed_response() -> None:
    client = FakeRedisClient()
    client.response_mode = "malformed-scan"

    with pytest.raises(RedisProtocolError, match="unexpected SCAN response"):
        client.scan("ip_*", count=2)


def test_scan_rejects_non_string_keys() -> None:
    client = FakeRedisClient()
    client.response_mode = "scan-non-string-key"

    with pytest.raises(RedisProtocolError, match="unexpected SCAN key"):
        client.scan("ip_*", count=2)
