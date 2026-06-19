from __future__ import annotations

import hashlib
from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol

from .key_filter import DecisionReason, KeyFilterPolicy


class KeyType(StrEnum):
    STRING = "string"
    LIST = "list"
    SET = "set"
    ZSET = "zset"
    HASH = "hash"
    STREAM = "stream"
    NONE = "none"
    UNKNOWN = "unknown"


class RelayErrorCode(StrEnum):
    SOURCE_DUMP_FAILED = "source_dump_failed"
    TARGET_PUBLISH_FAILED = "target_publish_failed"


@dataclass(frozen=True)
class RedisKeySnapshot:
    key: str
    key_type: KeyType
    ttl_ms: int
    serialized_payload: bytes


class TargetPublishStatus(StrEnum):
    PUBLISHED = "published"
    UNCHANGED = "unchanged"
    DUPLICATE = "duplicate"


@dataclass(frozen=True)
class TargetPublishResult:
    source_key: str
    target_key: str
    status: TargetPublishStatus
    event_id: str | None = None

    def changed(self) -> bool:
        return self.status == TargetPublishStatus.PUBLISHED


@dataclass(frozen=True)
class RelayBatchRequest:
    scan_count: int
    max_keys: int | None = None


@dataclass(frozen=True)
class RelayErrorSample:
    key: str
    stage: str
    code: RelayErrorCode
    error_type: str
    message: str


@dataclass(frozen=True)
class RelayBatchResult:
    scanned: int = 0
    copied: int = 0
    published: int = 0
    unchanged: int = 0
    duplicates: int = 0
    skipped: int = 0
    denied: int = 0
    missing: int = 0
    errors: int = 0
    error_samples: tuple[RelayErrorSample, ...] = ()


class SourceRedisPort(Protocol):
    def scan_keys(self, *, count: int) -> list[str]: ...
    def dump_key(self, key: str) -> RedisKeySnapshot | None: ...


class TargetRedisPort(Protocol):
    def publish_snapshot_if_changed(
        self,
        snapshot: RedisKeySnapshot,
    ) -> TargetPublishResult: ...


def replicate_allowed_keys_once(
    *,
    request: RelayBatchRequest,
    policy: KeyFilterPolicy,
    source: SourceRedisPort,
    target: TargetRedisPort,
) -> RelayBatchResult:
    result = RelayBatchResult()
    for key in source.scan_keys(count=request.scan_count):
        if request.max_keys is not None and result.scanned >= request.max_keys:
            break
        result = _replace(result, scanned=result.scanned + 1)
        decision = policy.decide(key)
        if decision.reason == DecisionReason.DENIED:
            result = _replace(result, denied=result.denied + 1)
            continue
        if not decision.should_copy:
            result = _replace(result, skipped=result.skipped + 1)
            continue
        try:
            snapshot = source.dump_key(key)
        except Exception as error:
            result = _with_error_sample(
                _replace(result, errors=result.errors + 1),
                key=key,
                stage="source_dump",
                code=RelayErrorCode.SOURCE_DUMP_FAILED,
                error=error,
            )
            continue
        if snapshot is None:
            result = _replace(result, missing=result.missing + 1)
            continue
        try:
            publish_result = target.publish_snapshot_if_changed(snapshot)
        except Exception as error:
            result = _with_error_sample(
                _replace(result, errors=result.errors + 1),
                key=key,
                stage="target_publish",
                code=RelayErrorCode.TARGET_PUBLISH_FAILED,
                error=error,
            )
            continue
        if publish_result.status == TargetPublishStatus.PUBLISHED:
            result = _replace(
                result,
                copied=result.copied + 1,
                published=result.published + 1,
            )
        elif publish_result.status == TargetPublishStatus.DUPLICATE:
            result = _replace(result, duplicates=result.duplicates + 1)
        elif publish_result.status == TargetPublishStatus.UNCHANGED:
            result = _replace(result, unchanged=result.unchanged + 1)
        else:
            result = _with_error_sample(
                _replace(result, errors=result.errors + 1),
                key=key,
                stage="target_publish",
                code=RelayErrorCode.TARGET_PUBLISH_FAILED,
                error=ValueError(
                    f"unsupported publish status: {publish_result.status}"
                ),
            )
    return result


def fingerprint(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _replace(result: RelayBatchResult, **changes: object) -> RelayBatchResult:
    values = {
        "scanned": result.scanned,
        "copied": result.copied,
        "published": result.published,
        "unchanged": result.unchanged,
        "duplicates": result.duplicates,
        "skipped": result.skipped,
        "denied": result.denied,
        "missing": result.missing,
        "errors": result.errors,
        "error_samples": result.error_samples,
    }
    values.update(changes)
    return RelayBatchResult(**values)


def _with_error_sample(
    result: RelayBatchResult,
    *,
    key: str,
    stage: str,
    code: RelayErrorCode,
    error: Exception,
    limit: int = 10,
) -> RelayBatchResult:
    if len(result.error_samples) >= limit:
        return result
    error_type = type(error).__name__
    return RelayBatchResult(
        scanned=result.scanned,
        copied=result.copied,
        published=result.published,
        unchanged=result.unchanged,
        duplicates=result.duplicates,
        skipped=result.skipped,
        denied=result.denied,
        missing=result.missing,
        errors=result.errors,
        error_samples=(
            *result.error_samples,
            RelayErrorSample(
                key=key,
                stage=stage,
                code=code,
                error_type=error_type,
                message=str(error),
            ),
        ),
    )
