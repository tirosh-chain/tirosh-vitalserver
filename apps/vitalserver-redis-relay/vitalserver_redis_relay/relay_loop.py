from __future__ import annotations

import time
from pathlib import Path

from .key_filter import relay_key_filter_policy
from .redis_client import RedisClient
from .replication import RelayBatchRequest, RelayBatchResult, replicate_allowed_keys_once
from .settings import RelaySettingsError, load_settings
from .status import write_status, write_unavailable_status


def run_forever(*, config_path: Path, status_path: Path) -> None:
    batches = 0
    totals = RelayBatchResult()
    while True:
        delay = 5.0
        try:
            settings = load_settings(config_path)
        except RelaySettingsError as error:
            write_unavailable_status(
                status_path,
                state="config_invalid",
                error=str(error),
            )
            time.sleep(delay)
            continue

        delay = settings.interval_seconds
        if not settings.enabled:
            write_status(
                status_path,
                settings=settings,
                state="disabled",
                batches=batches,
                totals=totals,
            )
            time.sleep(settings.status_interval_seconds)
            continue
        if settings.target is None:
            write_status(
                status_path,
                settings=settings,
                state="config_invalid",
                batches=batches,
                totals=totals,
                error="target is required when relay is enabled",
            )
            time.sleep(delay)
            continue

        policy = relay_key_filter_policy(
            scope=settings.scope,
            include_recorder_network_context=(
                settings.include_recorder_network_context
            ),
        )
        try:
            result = replicate_allowed_keys_once(
                request=RelayBatchRequest(scan_count=settings.scan_count),
                policy=policy,
                source=RedisClient(settings.source),
                target=RedisClient(settings.target),
            )
        except Exception as error:
            write_status(
                status_path,
                settings=settings,
                state="relay_failed",
                batches=batches,
                totals=totals,
                error=str(error),
            )
            time.sleep(delay)
            continue

        batches += 1
        totals = _add(totals, result)
        state = "running" if result.errors == 0 else "running_with_errors"
        write_status(
            status_path,
            settings=settings,
            state=state,
            batch=result,
            batches=batches,
            totals=totals,
        )
        time.sleep(delay)


def _add(left: RelayBatchResult, right: RelayBatchResult) -> RelayBatchResult:
    return RelayBatchResult(
        scanned=left.scanned + right.scanned,
        copied=left.copied + right.copied,
        unchanged=left.unchanged + right.unchanged,
        skipped=left.skipped + right.skipped,
        denied=left.denied + right.denied,
        missing=left.missing + right.missing,
        errors=left.errors + right.errors,
    )
