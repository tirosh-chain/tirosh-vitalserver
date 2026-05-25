from __future__ import annotations

import json
from pathlib import Path

from vitaldb_observer.collector import VitalDBCollector
from vitaldb_observer.config import ObserverSettings


class FakeRedis:
    def __init__(
        self, values: dict[str, str], sets: dict[str, list[str]] | None = None
    ) -> None:
        self.values = values
        self.sets = sets or {}

    def ping(self) -> bool:
        return True

    def get(self, key: str) -> str | None:
        return self.values.get(key)

    def smembers(self, key: str) -> list[str]:
        return self.sets.get(key, [])

    def keys(self, pattern: str) -> list[str]:
        if pattern.endswith("*"):
            prefix = pattern[:-1]
            return sorted(key for key in self.values if key.startswith(prefix))
        return [pattern] if pattern in self.values else []


def test_collector_builds_observation_from_redis_and_access_log(tmp_path: Path) -> None:
    access_log = tmp_path / "access.jsonl"
    access_log.write_text(
        json.dumps(
            {
                "time": "2026-05-25T00:00:00Z",
                "remote_addr": "10.0.0.10",
                "remote_port": "50000",
                "request_uri": "/socket.io/?EIO=3",
                "status": "101",
                "upstream_status": "101",
                "upstream_response_time": "0.01",
                "http_upgrade": "websocket",
            }
        )
        + "\n",
        encoding="utf-8",
    )
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_A": "10.0.0.10",
                "utime_VR_A": "9999999999",
                "vrver_VR_A": "1.0.0",
                "info_VR_A": "OR-1",
                "beds:bed-1": json.dumps({"name": "Bed 1", "vrcode": "VR_A"}),
                "utime_bed-1": "9999999999",
                "devs_bed-1": "device-json",
                "filts_bed-1": "filter-json",
            },
            sets={"beds": ["bed-1"]},
        ),
        settings=_settings(access_log),
    )

    document = collector.collect().as_json()

    assert document["ready"] is True
    assert document["recorders"][0]["vrcode"] == "VR_A"
    assert document["recorders"][0]["online"] is True
    assert document["beds"][0]["name"] == "Bed 1"
    assert document["devices"][0]["rawValue"] == "device-json"
    assert document["filters"][0]["rawValue"] == "filter-json"
    assert document["proxyConnections"][0]["websocketHandshake"] is True


def test_collector_detects_duplicate_ip() -> None:
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_A": "10.0.0.10",
                "ip_VR_B": "10.0.0.10",
                "utime_VR_A": "9999999999",
                "utime_VR_B": "9999999999",
            }
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()

    assert [anomaly["kind"] for anomaly in document["anomalies"]] == ["duplicate-ip"]


def _settings(access_log: Path | None = None) -> ObserverSettings:
    return ObserverSettings(
        host="127.0.0.1",
        port=8080,
        redis_host="redis",
        redis_port=6379,
        redis_timeout_seconds=1,
        recorder_online_threshold_seconds=120,
        access_log_path=str(access_log) if access_log else "",
        access_log_limit=20,
    )
