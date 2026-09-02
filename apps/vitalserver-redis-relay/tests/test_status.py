import json
from pathlib import Path

from vitalserver_redis_relay.key_filter import RelayScope
from vitalserver_redis_relay.replication import (
    RelayBatchResult,
    RelayErrorCode,
    RelayErrorSample,
)
from vitalserver_redis_relay.settings import (
    RedisEndpoint,
    RelaySettings,
    default_publish_contract,
)
from vitalserver_redis_relay.status import (
    build_status_document,
    build_unavailable_status_document,
    write_status_artifact,
)


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
        publish_contract=default_publish_contract(),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )

    document = build_status_document(
        settings=settings,
        state="running",
        batch=RelayBatchResult(copied=1, published=1),
        last_success_at="2026-06-18T00:00:01Z",
    )
    write_status_artifact(status_path, document)

    artifact_document = json.loads(status_path.read_text())
    rendered = status_path.read_text()
    assert artifact_document == document
    assert document["targetUrl"] == "redis://target:6379/0"
    assert document["targetUsernameConfigured"] is True
    assert document["targetPasswordConfigured"] is True
    assert document["batches"] == 0
    assert document["totals"]["copied"] == 0
    assert document["lastBatch"]["copied"] == 1
    assert document["lastBatch"]["published"] == 1
    assert document["publishEventStreamKey"] == "vitalserver:relay:events"
    assert len(document["settingsFingerprint"]) == 64
    assert document["lastSuccessAt"] == "2026-06-18T00:00:01Z"
    assert document["lastErrorAt"] is None
    assert document["lastErrorSamples"] == []
    assert "secret" not in rendered
    assert "default@" not in rendered
    assert "secret" not in repr(settings)
    assert "default" not in repr(settings.target)


def test_status_fingerprint_changes_when_connection_contract_changes(
    tmp_path: Path,
) -> None:
    first_status_path = tmp_path / "first.json"
    second_status_path = tmp_path / "second.json"
    base = RelaySettings(
        enabled=True,
        source=RedisEndpoint(host="redis", port=6379, database=0),
        target=RedisEndpoint(host="target", port=6379, database=0),
        publish_contract=default_publish_contract(),
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
        publish_contract=default_publish_contract(),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )

    write_status_artifact(
        first_status_path,
        build_status_document(settings=base, state="running"),
    )
    write_status_artifact(
        second_status_path,
        build_status_document(settings=changed, state="running"),
    )

    first = json.loads(first_status_path.read_text())
    second = json.loads(second_status_path.read_text())
    assert first["settingsFingerprint"] != second["settingsFingerprint"]


def test_status_fingerprint_ignores_credential_values() -> None:
    left = RelaySettings(
        enabled=True,
        source=RedisEndpoint(
            host="redis",
            port=6379,
            database=0,
            password="secret-a",
        ),
        target=RedisEndpoint(
            host="target",
            port=6379,
            database=0,
            username="user-a",
            password="secret-a",
        ),
        publish_contract=default_publish_contract(),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )
    right = RelaySettings(
        enabled=True,
        source=RedisEndpoint(
            host="redis",
            port=6379,
            database=0,
            password="secret-b",
        ),
        target=RedisEndpoint(
            host="target",
            port=6379,
            database=0,
            username="user-b",
            password="secret-b",
        ),
        publish_contract=default_publish_contract(),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )

    left_document = build_status_document(settings=left, state="running")
    right_document = build_status_document(settings=right, state="running")

    assert left_document["settingsFingerprint"] == right_document["settingsFingerprint"]
    assert left_document["targetUsernameConfigured"] is True
    assert left_document["targetPasswordConfigured"] is True
    assert "secret-a" not in repr(left)
    assert "user-a" not in repr(left)
    assert "secret-b" not in repr(right)
    assert "user-b" not in repr(right)


def test_unavailable_status_reports_explicit_error_observation(tmp_path: Path) -> None:
    status_path = tmp_path / "status.json"

    document = build_unavailable_status_document(
        state="config_invalid",
        error="config file missing",
    )
    write_status_artifact(status_path, document)

    artifact_document = json.loads(status_path.read_text())
    assert artifact_document == document
    assert document["enabled"] is False
    assert document["state"] == "config_invalid"
    assert document["scope"] is None
    assert document["settingsFingerprint"] is None
    assert document["lastSuccessAt"] is None
    assert document["lastErrorAt"] == document["observedAt"]
    assert document["lastError"] == "config file missing"
    assert document["lastErrorSamples"] == []


def test_status_reports_last_batch_error_samples(tmp_path: Path) -> None:
    status_path = tmp_path / "status.json"
    settings = RelaySettings(
        enabled=True,
        source=RedisEndpoint(host="redis", port=6379, database=0),
        target=RedisEndpoint(host="target", port=6379, database=0),
        publish_contract=default_publish_contract(),
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
        interval_seconds=1.0,
        scan_count=1000,
        status_interval_seconds=5.0,
    )

    document = build_status_document(
        settings=settings,
        state="running_with_errors",
        batch=RelayBatchResult(
            errors=1,
            error_samples=(
                RelayErrorSample(
                    key="beds",
                    stage="target_publish",
                    code=RelayErrorCode.TARGET_PUBLISH_FAILED,
                    error_type="TimeoutError",
                    message="timed out",
                ),
            ),
        ),
        error="relay batch completed with errors",
        last_error_at="2026-06-18T00:00:02Z",
    )
    write_status_artifact(status_path, document)

    artifact_document = json.loads(status_path.read_text())
    assert artifact_document == document
    assert "error_samples" not in document["lastBatch"]
    assert "error_samples" not in document["totals"]
    assert document["lastErrorSamples"] == [
        {
            "key": "beds",
            "stage": "target_publish",
            "code": "target_publish_failed",
            "errorType": "TimeoutError",
            "message": "timed out",
        },
    ]
