from __future__ import annotations

import json
import time
from pathlib import Path

from vitaldb_observer.collector import VitalDBCollector
from vitaldb_observer.config import ObserverSettings


class FakeRedis:
    def __init__(
        self,
        values: dict[str, str],
        sets: dict[str, list[str]] | None = None,
        lists: dict[str, list[str]] | None = None,
    ) -> None:
        self.values = values
        self.sets = sets or {}
        self.lists = lists or {}

    def ping(self) -> bool:
        return True

    def get(self, key: str) -> str | None:
        return self.values.get(key)

    def smembers(self, key: str) -> list[str]:
        return self.sets.get(key, [])

    def lrange(self, key: str, start: int, stop: int) -> list[str]:
        values = self.lists.get(key, [])
        if start < 0:
            start = max(len(values) + start, 0)
        if stop < 0:
            stop = len(values) + stop
        return values[start : stop + 1]

    def scan(self, pattern: str) -> list[str]:
        if pattern.endswith("*"):
            prefix = pattern[:-1]
            return sorted(key for key in self.values if key.startswith(prefix))
        return [pattern] if pattern in self.values else []


def test_collector_builds_observation_from_redis_and_access_log(tmp_path: Path) -> None:
    now = str(time.time() - 1)
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
                "utime_VR_A": now,
                "vrver_VR_A": "1.0.0",
                "info_VR_A": "OR-1",
                "beds:bed-1": json.dumps({"name": "Bed 1", "vrcode": "VR_A"}),
                "utime_bed-1": now,
                "devs_bed-1": "device-json",
                "filts_bed-1": "filter-json",
            },
            sets={"beds": ["bed-1"], "vrs": ["VR_A"]},
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


def test_collector_summarizes_recorder_activity_from_audit_events() -> None:
    now = time.time()
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_A": "10.0.0.10",
                "utime_VR_A": str(now - 1),
            },
            sets={"vrs": ["VR_A"]},
            lists={
                "vitalserver:audit_events": [
                    json.dumps(
                        {
                            "event_type": "send_data",
                            "ts": _iso(now - 20),
                            "payload_summary": {
                                "vrcode": "VR_A",
                                "bytes": 100,
                                "rooms_count": 2,
                            },
                        }
                    ),
                    json.dumps(
                        {
                            "event_type": "send_data",
                            "ts": _iso(now - 10),
                            "payload_summary": {
                                "vrcode": "VR_A",
                                "bytes": 150,
                                "rooms_count": 3,
                            },
                        }
                    ),
                    json.dumps(
                        {
                            "event_type": "send_data",
                            "ts": _iso(now - 400),
                            "payload_summary": {
                                "vrcode": "VR_A",
                                "bytes": 999,
                                "rooms_count": 9,
                            },
                        }
                    ),
                ]
            },
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()
    activity = document["recorders"][0]["activity"]

    assert activity["windowSeconds"] == 300
    assert activity["messageCount"] == 2
    assert activity["byteCount"] == 250
    assert activity["roomCount"] == 5
    assert activity["bytesPerSecond"] == 0.8
    assert activity["messagesPerSecond"] == 0.007
    assert [bucket["messageCount"] for bucket in activity["buckets"]] == [2]
    assert activity["buckets"][0]["bucketSeconds"] == 60
    assert activity["buckets"][0]["byteCount"] == 250


def test_collector_does_not_promote_bed_vrcode_to_recorder() -> None:
    now = str(time.time() - 1)
    bed_id = "d8e1436f3f1acfedc4b481d6b12d063134287810"
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_A": "10.0.0.10",
                "utime_VR_A": now,
                f"beds:{bed_id}": json.dumps({"name": "Bed A", "vrcode": "VR_A"}),
                f"utime_{bed_id}": now,
            },
            sets={"beds": [bed_id]},
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()

    assert document["recorders"] == []


def test_collector_does_not_promote_bed_activity_to_recorder() -> None:
    now = time.time()
    bed_id = "d8e1436f3f1acfedc4b481d6b12d063134287810"
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                f"beds:{bed_id}": json.dumps({"name": "Bed A"}),
                f"utime_{bed_id}": str(now - 1),
            },
            sets={"beds": [bed_id], "vrs": []},
            lists={
                "vitalserver:audit_events": [
                    json.dumps(
                        {
                            "event_type": "send_data",
                            "ts": _iso(now - 10),
                            "payload_summary": {
                                "vrcode": bed_id,
                                "bytes": 100,
                                "rooms_count": 1,
                            },
                        }
                    )
                ]
            },
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()

    assert document["recorders"] == []


def test_collector_accepts_camel_case_activity_events() -> None:
    now = time.time()
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_A": "10.0.0.10",
                "utime_VR_A": str(now - 1),
            },
            sets={"vrs": ["VR_A"]},
            lists={
                "vitalserver:audit_events": [
                    json.dumps(
                        {
                            "eventType": "send_data",
                            "observedAt": _iso(now - 10),
                            "payloadSummary": {
                                "vrcode": "VR_A",
                                "byteCount": 128,
                                "roomsCount": 2,
                            },
                        }
                    )
                ]
            },
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()
    activity = document["recorders"][0]["activity"]

    assert activity["messageCount"] == 1
    assert activity["byteCount"] == 128
    assert activity["roomCount"] == 2
    assert activity["buckets"][0]["messageCount"] == 1


def test_collector_detects_duplicate_ip() -> None:
    now = str(time.time() - 1)
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_A": "10.0.0.10",
                "ip_VR_B": "10.0.0.10",
                "utime_VR_A": now,
                "utime_VR_B": now,
            },
            sets={"vrs": ["VR_A", "VR_B"]},
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()

    assert [anomaly["kind"] for anomaly in document["anomalies"]] == ["duplicate-ip"]
    assert [anomaly["severity"] for anomaly in document["anomalies"]] == ["warning"]


def test_collector_reads_recent_access_log_tail_only(tmp_path: Path) -> None:
    access_log = tmp_path / "access.jsonl"
    stale_line = json.dumps({"request_uri": "/old"})
    current_line = json.dumps({"request_uri": "/socket.io/?EIO=3"})
    access_log.write_text(
        (stale_line + "\n") * 40000 + current_line + "\n",
        encoding="utf-8",
    )
    collector = VitalDBCollector(
        redis_client=FakeRedis(values={}),
        settings=_settings(access_log),
    )

    document = collector.collect().as_json()

    proxy_connections = document["proxyConnections"]
    assert len(proxy_connections) < 40001
    assert proxy_connections[-1]["requestURI"] == "/socket.io/?EIO=3"


def test_collector_treats_future_recorder_timestamp_as_stale() -> None:
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_A": "10.0.0.10",
                "utime_VR_A": "9999999999",
            },
            sets={"vrs": ["VR_A"]},
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()

    assert document["recorders"][0]["online"] is False
    assert document["recorders"][0]["stale"] is True


def test_collector_allows_subsecond_timestamp_skew() -> None:
    observed = int(time.time())
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_A": "10.0.0.10",
                "utime_VR_A": str(observed + 0.5),
            },
            sets={"vrs": ["VR_A"]},
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()

    assert document["recorders"][0]["online"] is True
    assert document["recorders"][0]["stale"] is False


def test_collector_ignores_deleted_recorder_status_keys() -> None:
    now = str(time.time() - 1)
    collector = VitalDBCollector(
        redis_client=FakeRedis(
            values={
                "ip_VR_DELETED": "10.0.0.10",
                "utime_VR_DELETED": now,
            },
            sets={"vrs": []},
        ),
        settings=_settings(),
    )

    document = collector.collect().as_json()

    assert document["recorders"] == []


def _settings(access_log: Path | None = None) -> ObserverSettings:
    return ObserverSettings(
        host="127.0.0.1",
        port=8080,
        redis_host="redis",
        redis_port=6379,
        redis_timeout_seconds=1,
        recorder_online_threshold_seconds=120,
        recorder_activity_window_seconds=300,
        audit_redis_list="vitalserver:audit_events",
        audit_event_limit=1000,
        access_log_path=str(access_log) if access_log else "",
        access_log_limit=20,
    )


def _iso(timestamp: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(timestamp))
