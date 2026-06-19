import json
from pathlib import Path

from vitalserver_redis_relay.key_filter import RelayScope
from vitalserver_redis_relay.replication import RelayBatchResult
from vitalserver_redis_relay.settings import RedisEndpoint, RelaySettings
from vitalserver_redis_relay.status import write_status, write_unavailable_status


def test_status_masks_password(tmp_path: Path) -> None:
    status_path = tmp_path / "status.json"
    settings = RelaySettings(
        enabled=True,
        source=RedisEndpoint(host="redis", port=6379, database=0),
        target=RedisEndpoint(
            host="target",
            port=6379,
            database=0,
            username="default",
            password="secret",
        ),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )

    write_status(
        status_path,
        settings=settings,
        state="running",
        batch=RelayBatchResult(copied=1),
        last_success_at="2026-06-18T00:00:01Z",
    )

    document = json.loads(status_path.read_text())
    assert document["targetUrl"] == "redis://default@target:6379/0"
    assert document["targetPasswordConfigured"] is True
    assert document["batches"] == 0
    assert document["totals"]["copied"] == 0
    assert document["lastBatch"]["copied"] == 1
    assert len(document["settingsFingerprint"]) == 64
    assert document["lastSuccessAt"] == "2026-06-18T00:00:01Z"
    assert document["lastErrorAt"] is None
    assert "secret" not in status_path.read_text()


def test_status_fingerprint_changes_when_connection_contract_changes(
    tmp_path: Path,
) -> None:
    first_status_path = tmp_path / "first.json"
    second_status_path = tmp_path / "second.json"
    base = RelaySettings(
        enabled=True,
        source=RedisEndpoint(host="redis", port=6379, database=0),
        target=RedisEndpoint(host="target", port=6379, database=0),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )
    changed = RelaySettings(
        enabled=True,
        source=RedisEndpoint(host="redis", port=6379, database=0),
        target=RedisEndpoint(host="target", port=6380, database=0),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )

    write_status(first_status_path, settings=base, state="running")
    write_status(second_status_path, settings=changed, state="running")

    first = json.loads(first_status_path.read_text())
    second = json.loads(second_status_path.read_text())
    assert first["settingsFingerprint"] != second["settingsFingerprint"]


def test_unavailable_status_reports_explicit_error_observation(tmp_path: Path) -> None:
    status_path = tmp_path / "status.json"

    write_unavailable_status(
        status_path,
        state="config_invalid",
        error="config file missing",
    )

    document = json.loads(status_path.read_text())
    assert document["enabled"] is False
    assert document["state"] == "config_invalid"
    assert document["settingsFingerprint"] is None
    assert document["lastSuccessAt"] is None
    assert document["lastErrorAt"] == document["observedAt"]
    assert document["lastError"] == "config file missing"
