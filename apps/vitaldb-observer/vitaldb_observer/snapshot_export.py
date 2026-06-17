from __future__ import annotations

import base64
import re
from dataclasses import dataclass, field
from fnmatch import fnmatchcase
from typing import Any, Protocol

from .time import utc_now_iso


class RedisSnapshotReader(Protocol):
    def scan_page(
        self,
        *,
        cursor: str,
        pattern: str = "*",
        count: int = 1000,
    ) -> tuple[str, list[str]]: ...
    def key_type(self, key: str) -> str: ...
    def pttl(self, key: str) -> int: ...
    def dump(self, key: str) -> bytes | None: ...


@dataclass(frozen=True)
class RedisSnapshotKeyDocument:
    key: str
    key_type: str
    ttl_ms: int
    dump_base64: str

    def as_json(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "keyType": self.key_type,
            "ttlMs": self.ttl_ms,
            "dumpBase64": self.dump_base64,
        }


@dataclass(frozen=True)
class RedisSnapshotReadIssue:
    key: str | None
    message: str

    def as_json(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "message": self.message,
        }


@dataclass(frozen=True)
class RedisSnapshotPageDocument:
    observed_at: str
    cursor: str
    next_cursor: str
    complete: bool
    scan_count: int
    limit: int
    scanned: int
    copied: int
    skipped: int
    keys: list[RedisSnapshotKeyDocument] = field(default_factory=list)
    read_issues: list[RedisSnapshotReadIssue] = field(default_factory=list)

    def as_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": 1,
            "source": "vitaldb-observer",
            "observedAt": self.observed_at,
            "cursor": self.cursor,
            "nextCursor": self.next_cursor,
            "complete": self.complete,
            "scanCount": self.scan_count,
            "limit": self.limit,
            "scanned": self.scanned,
            "copied": self.copied,
            "skipped": self.skipped,
            "keys": [item.as_json() for item in self.keys],
            "readIssues": [issue.as_json() for issue in self.read_issues],
        }


DEFAULT_ALLOW_REGEXES: tuple[str, ...] = (
    r"^[0-9a-f]{40}[0-9]+\.[0-9]+$",
    r"^dts_[0-9a-f]{40}$",
    r"^dts_trend_result_[0-9a-f]{40}$",
    r"^trend_[0-9a-f]{40}_[0-9]+$",
)

DEFAULT_DENY_GLOBS: tuple[str, ...] = (
    "sess:*",
    "users",
    "users:*",
    "ws_ticket:*",
    "auth:*",
    "token:*",
    "credential:*",
    "secret:*",
    "account_lockout:*",
    "login_attempt:*",
    "rate_limit:*",
    "vitalserver:audit_events",
    "websocket:*",
    "session:*:hct",
)


class RedisSnapshotExporter:
    def __init__(
        self,
        redis_client: RedisSnapshotReader,
        *,
        allow_regexes: tuple[str, ...] = DEFAULT_ALLOW_REGEXES,
        deny_globs: tuple[str, ...] = DEFAULT_DENY_GLOBS,
    ) -> None:
        self._redis = redis_client
        self._allow_regexes = tuple(re.compile(pattern) for pattern in allow_regexes)
        self._deny_globs = deny_globs

    def page(
        self,
        *,
        cursor: str,
        scan_count: int,
        limit: int,
    ) -> RedisSnapshotPageDocument:
        next_cursor, page_keys = self._redis.scan_page(
            cursor=cursor,
            pattern="*",
            count=scan_count,
        )
        copied_keys: list[RedisSnapshotKeyDocument] = []
        read_issues: list[RedisSnapshotReadIssue] = []
        skipped = 0

        for key in sorted(page_keys):
            if not self._allowed(key):
                skipped += 1
                continue
            if len(copied_keys) >= limit:
                skipped += 1
                continue

            document = self._snapshot_key(key, read_issues)
            if document is None:
                skipped += 1
                continue
            copied_keys.append(document)

        return RedisSnapshotPageDocument(
            observed_at=utc_now_iso(),
            cursor=cursor,
            next_cursor=next_cursor,
            complete=next_cursor == "0",
            scan_count=scan_count,
            limit=limit,
            scanned=len(page_keys),
            copied=len(copied_keys),
            skipped=skipped,
            keys=copied_keys,
            read_issues=read_issues,
        )

    def _snapshot_key(
        self,
        key: str,
        read_issues: list[RedisSnapshotReadIssue],
    ) -> RedisSnapshotKeyDocument | None:
        key_type = self._redis.key_type(key)
        if key_type == "none":
            read_issues.append(
                RedisSnapshotReadIssue(key=key, message="key disappeared during read")
            )
            return None
        payload = self._redis.dump(key)
        if payload is None:
            read_issues.append(
                RedisSnapshotReadIssue(key=key, message="key dump returned nil")
            )
            return None
        return RedisSnapshotKeyDocument(
            key=key,
            key_type=key_type,
            ttl_ms=self._redis.pttl(key),
            dump_base64=base64.b64encode(payload).decode("ascii"),
        )

    def _allowed(self, key: str) -> bool:
        for pattern in self._deny_globs:
            if fnmatchcase(key, pattern):
                return False
        return any(pattern.fullmatch(key) for pattern in self._allow_regexes)
