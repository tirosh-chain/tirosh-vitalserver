from __future__ import annotations

from typing import Any

from vitaldb_observer.redis_client import RedisClient


class FakeRedisClient(RedisClient):
    def __init__(self) -> None:
        self.commands: list[tuple[str, ...]] = []

    def command(self, *parts: str) -> Any:
        self.commands.append(parts)
        cursor = parts[1]
        if cursor == "0":
            return ["7", ["ip_A", "ip_B"]]
        return ["0", ["ip_B", "ip_C", 1]]


def test_scan_collects_unique_keys_without_keys_command() -> None:
    client = FakeRedisClient()

    assert client.scan("ip_*", count=2) == ["ip_A", "ip_B", "ip_C"]
    assert client.commands == [
        ("SCAN", "0", "MATCH", "ip_*", "COUNT", "2"),
        ("SCAN", "7", "MATCH", "ip_*", "COUNT", "2"),
    ]
