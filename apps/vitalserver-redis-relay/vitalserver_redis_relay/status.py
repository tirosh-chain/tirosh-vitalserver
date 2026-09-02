from __future__ import annotations

import json
import os
import tempfile
from contextlib import suppress
from dataclasses import dataclass
from datetime import UTC, datetime
from hashlib import sha256
from pathlib import Path

from .replication import RelayBatchResult
from .settings import RedisEndpoint, RelaySettings
from .status_publisher import StatusPublishOutcome, StatusPublishResult


@dataclass(frozen=True)
class RelayStatus:
    schema_version: int
    observed_at: str
    enabled: bool
    state: str
    scope: str
    target_url: str | None
    target_host: str | None
    target_port: int | None
    target_database: int | None
    target_tls: bool | None
    target_username_configured: bool
    target_password_configured: bool
    settings_fingerprint: str
    publish_target_key_prefix: str
    publish_event_stream_key: str
    publish_publisher_id: str
    batches: int
    totals: dict[str, int]
    last_batch: dict[str, int] | None
    last_success_at: str | None
    last_error_at: str | None
    last_error: str | None
    last_error_samples: list[dict[str, str]]


def status_timestamp() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def build_status_document(
    *,
    settings: RelaySettings,
    state: str,
    batch: RelayBatchResult | None = None,
    batches: int = 0,
    totals: RelayBatchResult | None = None,
    error: str | None = None,
    last_success_at: str | None = None,
    last_error_at: str | None = None,
) -> dict[str, object]:
    target = settings.target
    status = RelayStatus(
        schema_version=1,
        observed_at=status_timestamp(),
        enabled=settings.enabled,
        state=state,
        scope=settings.scope.value,
        target_url=_target_url(target) if target else None,
        target_host=target.host if target else None,
        target_port=target.port if target else None,
        target_database=target.database if target else None,
        target_tls=target.tls if target else None,
        target_username_configured=bool(target and target.username),
        target_password_configured=bool(target and target.password),
        settings_fingerprint=_settings_fingerprint(settings),
        publish_target_key_prefix=settings.publish_contract.target_key_prefix,
        publish_event_stream_key=settings.publish_contract.event_stream_key,
        publish_publisher_id=settings.publish_contract.publisher_id,
        batches=batches,
        totals=_batch_counts(totals or RelayBatchResult()),
        last_batch=_batch_counts(batch) if batch else None,
        last_success_at=last_success_at,
        last_error_at=last_error_at,
        last_error=error,
        last_error_samples=_error_samples(batch),
    )
    return _wire_status(status)


class FileStatusPublisher:
    name = "file"

    def __init__(self, path: Path) -> None:
        self.path = path

    def publish(self, document: dict[str, object]) -> StatusPublishResult:
        try:
            write_status_artifact(self.path, document)
        except OSError as error:
            return StatusPublishResult(
                outcomes=(
                    StatusPublishOutcome(
                        publisher=self.name,
                        published=False,
                        error=f"status file write failed: {error}",
                    ),
                )
            )
        return StatusPublishResult(
            outcomes=(
                StatusPublishOutcome(publisher=self.name, published=True),
            )
        )


def write_status_artifact(path: Path, document: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(document, sort_keys=True) + "\n"
    descriptor, temporary = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            descriptor = -1
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except OSError:
        if descriptor >= 0:
            os.close(descriptor)
        with suppress(FileNotFoundError):
            os.unlink(temporary)
        raise


def build_unavailable_status_document(*, state: str, error: str) -> dict[str, object]:
    observed_at = status_timestamp()
    return {
        "schemaVersion": 1,
        "observedAt": observed_at,
        "enabled": False,
        "state": state,
        "scope": None,
        "targetUrl": None,
        "targetHost": None,
        "targetPort": None,
        "targetDatabase": None,
        "targetTLS": None,
        "targetUsernameConfigured": False,
        "targetPasswordConfigured": False,
        "settingsFingerprint": None,
        "publishTargetKeyPrefix": None,
        "publishEventStreamKey": None,
        "publishPublisherId": None,
        "batches": 0,
        "totals": _batch_counts(RelayBatchResult()),
        "lastBatch": None,
        "lastSuccessAt": None,
        "lastErrorAt": observed_at,
        "lastError": error,
        "lastErrorSamples": [],
    }


def _wire_status(status: RelayStatus) -> dict[str, object]:
    return {
        "schemaVersion": status.schema_version,
        "observedAt": status.observed_at,
        "enabled": status.enabled,
        "state": status.state,
        "scope": status.scope,
        "targetUrl": status.target_url,
        "targetHost": status.target_host,
        "targetPort": status.target_port,
        "targetDatabase": status.target_database,
        "targetTLS": status.target_tls,
        "targetUsernameConfigured": status.target_username_configured,
        "targetPasswordConfigured": status.target_password_configured,
        "settingsFingerprint": status.settings_fingerprint,
        "publishTargetKeyPrefix": status.publish_target_key_prefix,
        "publishEventStreamKey": status.publish_event_stream_key,
        "publishPublisherId": status.publish_publisher_id,
        "batches": status.batches,
        "totals": status.totals,
        "lastBatch": status.last_batch,
        "lastSuccessAt": status.last_success_at,
        "lastErrorAt": status.last_error_at,
        "lastError": status.last_error,
        "lastErrorSamples": status.last_error_samples,
    }


def _batch_counts(result: RelayBatchResult) -> dict[str, int]:
    return {
        "scanned": result.scanned,
        "copied": result.copied,
        "published": result.published,
        "unchanged": result.unchanged,
        "duplicates": result.duplicates,
        "skipped": result.skipped,
        "denied": result.denied,
        "missing": result.missing,
        "errors": result.errors,
    }


def _error_samples(result: RelayBatchResult | None) -> list[dict[str, str]]:
    if result is None:
        return []
    return [
        {
            "key": sample.key,
            "stage": sample.stage,
            "code": sample.code.value,
            "errorType": sample.error_type,
            "message": sample.message,
        }
        for sample in result.error_samples
    ]


def _target_url(target: RedisEndpoint) -> str:
    scheme = "rediss" if target.tls else "redis"
    database = f"/{target.database}" if target.database else "/0"
    return f"{scheme}://{target.host}:{target.port}{database}"


def _endpoint_fingerprint(endpoint: RedisEndpoint | None) -> dict[str, object] | None:
    if endpoint is None:
        return None
    return {
        "host": endpoint.host,
        "port": endpoint.port,
        "database": endpoint.database,
        "tls": endpoint.tls,
        "usernameConfigured": bool(endpoint.username),
        "passwordConfigured": bool(endpoint.password),
    }


def _settings_fingerprint(settings: RelaySettings) -> str:
    payload = {
        "enabled": settings.enabled,
        "scope": settings.scope.value,
        "includeRecorderNetworkContext": settings.include_recorder_network_context,
        "intervalSeconds": settings.interval_seconds,
        "scanCount": settings.scan_count,
        "statusIntervalSeconds": settings.status_interval_seconds,
        "publish": {
            "targetKeyPrefix": settings.publish_contract.target_key_prefix,
            "eventStreamKey": settings.publish_contract.event_stream_key,
            "fingerprintHashKey": settings.publish_contract.fingerprint_hash_key,
            "publishDedupeHashKey": (
                settings.publish_contract.publish_dedupe_hash_key
            ),
            "eventStreamMaxlen": settings.publish_contract.event_stream_maxlen,
            "publisherId": settings.publish_contract.publisher_id,
        },
        "source": _endpoint_fingerprint(settings.source),
        "target": _endpoint_fingerprint(settings.target),
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )
    return sha256(encoded).hexdigest()
