from vitalserver_redis_relay.key_filter import RelayScope, relay_key_filter_policy
from vitalserver_redis_relay.replication import (
    KeyType,
    RedisKeySnapshot,
    RelayBatchRequest,
    TargetRestoreResult,
    replicate_allowed_keys_once,
)


class FakeSource:
    def __init__(self) -> None:
        self.dumped: list[str] = []

    def scan_keys(self, *, count: int) -> list[str]:
        return [
            "beds",
            "token:secret",
            "ignored",
            "a" * 40 + "1778392870.112",
        ]

    def dump_key(self, key: str) -> RedisKeySnapshot | None:
        self.dumped.append(key)
        return RedisKeySnapshot(
            key=key,
            key_type=KeyType.STRING,
            ttl_ms=1000,
            serialized_payload=f"payload:{key}".encode(),
        )


class FakeTarget:
    def __init__(self) -> None:
        self.snapshots: list[RedisKeySnapshot] = []

    def restore_key(
        self,
        snapshot: RedisKeySnapshot,
        *,
        replace: bool,
    ) -> TargetRestoreResult:
        self.snapshots.append(snapshot)
        return TargetRestoreResult(
            source_key=snapshot.key,
            target_key=f"vitalserver:{snapshot.key}",
            changed=True,
        )


def test_replicate_allowed_keys_copies_allowed_and_denies_credentials() -> None:
    source = FakeSource()
    target = FakeTarget()

    result = replicate_allowed_keys_once(
        request=RelayBatchRequest(scan_count=1000),
        policy=relay_key_filter_policy(
            scope=RelayScope.VITAL_RECONSTRUCTION,
            include_recorder_network_context=False,
        ),
        source=source,
        target=target,
    )

    assert result.scanned == 4
    assert result.copied == 2
    assert result.denied == 1
    assert result.skipped == 1
    assert source.dumped == ["beds", "a" * 40 + "1778392870.112"]
    assert [snapshot.key for snapshot in target.snapshots] == source.dumped
