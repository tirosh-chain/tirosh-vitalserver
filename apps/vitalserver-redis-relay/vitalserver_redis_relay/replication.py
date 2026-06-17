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


@dataclass(frozen=True)
class RedisKeySnapshot:
    key: str
    key_type: KeyType
    ttl_ms: int
    serialized_payload: bytes


@dataclass(frozen=True)
class TargetRestoreResult:
    source_key: str
    target_key: str
    changed: bool


@dataclass(frozen=True)
class RelayBatchRequest:
    scan_count: int
    max_keys: int | None = None


@dataclass(frozen=True)
class RelayBatchResult:
    scanned: int = 0
    copied: int = 0
    unchanged: int = 0
    skipped: int = 0
    denied: int = 0
    missing: int = 0
    errors: int = 0


class SourceRedisPort(Protocol):
    def scan_keys(self, *, count: int) -> list[str]: ...
    def dump_key(self, key: str) -> RedisKeySnapshot | None: ...


class TargetRedisPort(Protocol):
    def restore_key(
        self,
        snapshot: RedisKeySnapshot,
        *,
        replace: bool,
    ) -> TargetRestoreResult: ...


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
            if snapshot is None:
                result = _replace(result, missing=result.missing + 1)
                continue
            restore_result = target.restore_key(snapshot, replace=True)
        except Exception:
            result = _replace(result, errors=result.errors + 1)
            continue
        if restore_result.changed:
            result = _replace(result, copied=result.copied + 1)
        else:
            result = _replace(result, unchanged=result.unchanged + 1)
    return result


def fingerprint(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _replace(result: RelayBatchResult, **changes: int) -> RelayBatchResult:
    values = {
        "scanned": result.scanned,
        "copied": result.copied,
        "unchanged": result.unchanged,
        "skipped": result.skipped,
        "denied": result.denied,
        "missing": result.missing,
        "errors": result.errors,
    }
    values.update(changes)
    return RelayBatchResult(**values)
