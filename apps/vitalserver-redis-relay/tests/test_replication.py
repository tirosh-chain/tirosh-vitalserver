from vitalserver_redis_relay.key_filter import RelayScope, relay_key_filter_policy
from vitalserver_redis_relay.replication import (
    KeyType,
    RedisKeySnapshot,
    RelayBatchRequest,
    RelayErrorCode,
    TargetPublishResult,
    TargetPublishStatus,
    replicate_allowed_keys_once,
)


class FakeSource:
    def __init__(
        self,
        *,
        keys: list[str] | None = None,
        fail_dump: bool = False,
    ) -> None:
        self.dumped: list[str] = []
        self._keys = keys or [
            "beds",
            "token:secret",
            "ignored",
            "a" * 40 + "1778392870.112",
        ]
        self._fail_dump = fail_dump

    def scan_keys(self, *, count: int) -> list[str]:
        return self._keys

    def dump_key(self, key: str) -> RedisKeySnapshot | None:
        self.dumped.append(key)
        if self._fail_dump:
            raise RuntimeError(f"dump failed for {key}")
        return RedisKeySnapshot(
            key=key,
            key_type=KeyType.STRING,
            ttl_ms=1000,
            serialized_payload=f"payload:{key}".encode(),
        )


class FakeTarget:
    def __init__(self) -> None:
        self.snapshots: list[RedisKeySnapshot] = []

    def publish_snapshot_if_changed(
        self,
        snapshot: RedisKeySnapshot,
    ) -> TargetPublishResult:
        self.snapshots.append(snapshot)
        return TargetPublishResult(
            source_key=snapshot.key,
            target_key=f"vitalserver:{snapshot.key}",
            status=TargetPublishStatus.PUBLISHED,
            event_id=f"event:{snapshot.key}",
        )


class FailingTarget:
    def publish_snapshot_if_changed(
        self,
        snapshot: RedisKeySnapshot,
    ) -> TargetPublishResult:
        raise TimeoutError(f"publish timed out for {snapshot.key}")


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
    assert result.published == 2
    assert result.denied == 1
    assert result.skipped == 1
    assert source.dumped == ["beds", "a" * 40 + "1778392870.112"]
    assert [snapshot.key for snapshot in target.snapshots] == source.dumped


def test_replicate_allowed_keys_records_error_samples() -> None:
    source = FakeSource()

    result = replicate_allowed_keys_once(
        request=RelayBatchRequest(scan_count=1000),
        policy=relay_key_filter_policy(
            scope=RelayScope.VITAL_RECONSTRUCTION,
            include_recorder_network_context=False,
        ),
        source=source,
        target=FailingTarget(),
    )

    assert result.scanned == 4
    assert result.errors == 2
    assert [sample.key for sample in result.error_samples] == [
        "beds",
        "a" * 40 + "1778392870.112",
    ]
    assert all(sample.stage == "target_publish" for sample in result.error_samples)
    assert all(
        sample.code == RelayErrorCode.TARGET_PUBLISH_FAILED
        for sample in result.error_samples
    )
    assert result.error_samples[0].error_type == "TimeoutError"
    assert "publish timed out" in result.error_samples[0].message


def test_replicate_allowed_keys_classifies_source_dump_failures() -> None:
    source = FakeSource(fail_dump=True)
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

    assert result.errors == 2
    assert result.copied == 0
    assert result.published == 0
    assert target.snapshots == []
    assert all(sample.stage == "source_dump" for sample in result.error_samples)
    assert all(
        sample.code == RelayErrorCode.SOURCE_DUMP_FAILED
        for sample in result.error_samples
    )
    assert result.error_samples[0].error_type == "RuntimeError"


def test_replicate_allowed_keys_limits_error_samples() -> None:
    keys = ["beds", *[f"{'a' * 40}{index}.100" for index in range(20)]]

    result = replicate_allowed_keys_once(
        request=RelayBatchRequest(scan_count=1000),
        policy=relay_key_filter_policy(
            scope=RelayScope.VITAL_RECONSTRUCTION,
            include_recorder_network_context=False,
        ),
        source=FakeSource(keys=keys),
        target=FailingTarget(),
    )

    assert result.errors == 21
    assert len(result.error_samples) == 10
    assert result.error_samples[0].key == "beds"
    assert result.error_samples[-1].key == f"{'a' * 40}8.100"
