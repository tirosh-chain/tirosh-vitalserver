from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path

from .replication import RelayBatchResult
from .settings import RedisEndpoint, RelaySettings


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
    batches: int
    totals: dict[str, int]
    last_batch: dict[str, int] | None
    last_error: str | None


def write_status(
    path: Path,
    *,
    settings: RelaySettings,
    state: str,
    batch: RelayBatchResult | None = None,
    batches: int = 0,
    totals: RelayBatchResult | None = None,
    error: str | None = None,
) -> None:
    target = settings.target
    status = RelayStatus(
        schema_version=1,
        observed_at=datetime.now(UTC).isoformat().replace("+00:00", "Z"),
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
        batches=batches,
        totals=asdict(totals or RelayBatchResult()),
        last_batch=asdict(batch) if batch else None,
        last_error=error,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(_wire_status(status), sort_keys=True) + "\n")


def write_unavailable_status(path: Path, *, state: str, error: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "observedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
                "enabled": False,
                "state": state,
                "scope": "unknown",
                "targetUrl": None,
                "targetHost": None,
                "targetPort": None,
                "targetDatabase": None,
                "targetTLS": None,
                "targetUsernameConfigured": False,
                "targetPasswordConfigured": False,
                "batches": 0,
                "totals": asdict(RelayBatchResult()),
                "lastBatch": None,
                "lastError": error,
            },
            sort_keys=True,
        )
        + "\n"
    )


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
        "batches": status.batches,
        "totals": status.totals,
        "lastBatch": status.last_batch,
        "lastError": status.last_error,
    }


def _target_url(target: RedisEndpoint) -> str:
    scheme = "rediss" if target.tls else "redis"
    userinfo = f"{target.username}@" if target.username else ""
    database = f"/{target.database}" if target.database else "/0"
    return f"{scheme}://{userinfo}{target.host}:{target.port}{database}"
