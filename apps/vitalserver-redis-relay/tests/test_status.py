import json
from pathlib import Path

from vitalserver_redis_relay.key_filter import RelayScope
from vitalserver_redis_relay.replication import RelayBatchResult
from vitalserver_redis_relay.settings import RedisEndpoint, RelaySettings
from vitalserver_redis_relay.status import write_status


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
    )

    document = json.loads(status_path.read_text())
    assert document["targetPasswordConfigured"] is True
    assert "secret" not in status_path.read_text()
