from __future__ import annotations

from collections.abc import Mapping
from typing import Any


class RuntimeSettingsContractError(ValueError):
    pass


REQUIRED_BOOLEAN_FIELDS = {
    "automaticBackupEnabled",
    "containerMemoryLimitsEnabled",
}
REQUIRED_INTEGER_FIELDS = {
    "backupRetentionCount",
    "publicPort",
    "recorderIngressContainerMemoryLimitMiB",
    "recorderIngressSendDataReplayBatchSize",
    "recorderIngressSendDataReplayMaxMiBPerSecond",
    "redisContainerMemoryLimitMiB",
    "vitalServerContainerMemoryLimitMiB",
}
REQUIRED_STRING_FIELDS = {
    "publicHost",
    "recorderIngressSendDataMode",
    "remoteConsoleURL",
    "vitalServerURL",
}
RECORDER_INGRESS_BOOLEAN_FIELDS = {
    "rawArchiveAutoExportEnabled",
    "rawArchiveEnabled",
}
RECORDER_INGRESS_INTEGER_FIELDS = {
    "rawArchiveAutoExportCursorStableSeconds",
    "rawArchiveAutoExportMaxAttempts",
    "rawArchiveAutoExportQuietSeconds",
    "rawArchiveAutoExportRequestTimeoutSeconds",
    "rawArchiveAutoExportRetryDelaySeconds",
    "rawArchiveAutoExportScanIntervalSeconds",
    "rawArchiveMaxFileMiB",
    "rawArchiveMaxFiles",
    "sendDataMaxPayloadMiB",
    "sendDataMaxPendingItems",
    "sendDataMaxPendingMiB",
    "sendDataRealtimeMaxPendingItems",
    "sendDataReplayAdaptiveMaxConcurrency",
    "sendDataReplayAdaptiveMinConcurrency",
    "sendDataReplayIntervalMs",
    "sendDataReplayMaxAttempts",
    "sendDataReplayTargetTimeoutMs",
    "sendDataReplayedMaxItems",
}


def validated_runtime_settings(source: Mapping[str, Any]) -> dict[str, Any]:
    document = dict(source)
    for field in REQUIRED_BOOLEAN_FIELDS:
        _require_bool(document, field)
    for field in REQUIRED_INTEGER_FIELDS:
        _require_positive_int(document, field)
    for field in REQUIRED_STRING_FIELDS:
        _require_string(document, field, allow_empty=True)

    schedule = document.get("backupScheduleTimes")
    if not isinstance(schedule, list) or not all(
        isinstance(value, str) and value.strip() for value in schedule
    ):
        raise RuntimeSettingsContractError(
            "runtime settings backupScheduleTimes must be a string list"
        )
    mode = document["recorderIngressSendDataMode"]
    if mode not in {"passthrough", "mirror_spool", "spool_only", "spool_and_replay"}:
        raise RuntimeSettingsContractError(
            "runtime settings recorderIngressSendDataMode is invalid"
        )
    if document["publicPort"] > 65535:
        raise RuntimeSettingsContractError(
            "runtime settings publicPort must be at most 65535"
        )

    recorder_ingress = document.get("recorderIngress")
    if not isinstance(recorder_ingress, Mapping):
        raise RuntimeSettingsContractError(
            "runtime settings recorderIngress must be an object"
        )
    ingress = dict(recorder_ingress)
    for field in RECORDER_INGRESS_BOOLEAN_FIELDS:
        _require_bool(ingress, field, prefix="recorderIngress.")
    for field in RECORDER_INGRESS_INTEGER_FIELDS:
        _require_positive_int(ingress, field, prefix="recorderIngress.")

    if (
        ingress["sendDataReplayAdaptiveMinConcurrency"]
        > ingress["sendDataReplayAdaptiveMaxConcurrency"]
    ):
        raise RuntimeSettingsContractError(
            "runtime settings recorderIngress adaptive concurrency range is invalid"
        )
    document["recorderIngress"] = ingress
    return document


def _require_bool(
    document: Mapping[str, Any], field: str, *, prefix: str = ""
) -> None:
    if not isinstance(document.get(field), bool):
        raise RuntimeSettingsContractError(
            f"runtime settings {prefix}{field} must be a boolean"
        )


def _require_positive_int(
    document: Mapping[str, Any], field: str, *, prefix: str = ""
) -> None:
    value = document.get(field)
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise RuntimeSettingsContractError(
            f"runtime settings {prefix}{field} must be a positive integer"
        )


def _require_string(
    document: Mapping[str, Any],
    field: str,
    *,
    prefix: str = "",
    allow_empty: bool = False,
) -> None:
    value = document.get(field)
    if not isinstance(value, str) or (not allow_empty and not value.strip()):
        raise RuntimeSettingsContractError(
            f"runtime settings {prefix}{field} must be a string"
        )
