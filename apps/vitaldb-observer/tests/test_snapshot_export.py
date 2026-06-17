from __future__ import annotations

import base64

from vitaldb_observer.snapshot_export import RedisSnapshotExporter


class FakeSnapshotRedis:
    def __init__(self) -> None:
        self.keys = [
            "users:admin",
            "dts_0123456789abcdef0123456789abcdef01234567",
            "0123456789abcdef0123456789abcdef012345671781691200.25",
            "token:admin",
        ]
        self.payloads = {
            "dts_0123456789abcdef0123456789abcdef01234567": b"dts-payload",
            "0123456789abcdef0123456789abcdef012345671781691200.25": b"waveform",
        }

    def scan_page(
        self,
        *,
        cursor: str,
        pattern: str = "*",
        count: int = 1000,
    ) -> tuple[str, list[str]]:
        return "0", self.keys

    def key_type(self, key: str) -> str:
        return "zset" if key.startswith("dts_") else "string"

    def pttl(self, key: str) -> int:
        return -1

    def dump(self, key: str) -> bytes | None:
        return self.payloads.get(key)


def test_snapshot_exporter_returns_only_allowlisted_binary_snapshots() -> None:
    exporter = RedisSnapshotExporter(FakeSnapshotRedis())

    document = exporter.page(cursor="0", scan_count=1000, limit=10).as_json()

    assert document["complete"] is True
    assert document["scanned"] == 4
    assert document["copied"] == 2
    assert document["skipped"] == 2
    assert [item["key"] for item in document["keys"]] == [
        "0123456789abcdef0123456789abcdef012345671781691200.25",
        "dts_0123456789abcdef0123456789abcdef01234567",
    ]
    assert document["keys"][0]["dumpBase64"] == base64.b64encode(b"waveform").decode(
        "ascii"
    )


def test_snapshot_exporter_limits_returned_keys_without_leaking_denied_keys() -> None:
    exporter = RedisSnapshotExporter(FakeSnapshotRedis())

    document = exporter.page(cursor="0", scan_count=1000, limit=1).as_json()

    assert document["copied"] == 1
    assert document["skipped"] == 3
    assert len(document["keys"]) == 1
