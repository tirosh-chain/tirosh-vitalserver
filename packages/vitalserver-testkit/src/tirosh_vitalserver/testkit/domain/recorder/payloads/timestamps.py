"""Timestamp normalization helpers for recorder payloads."""

from __future__ import annotations

import time
from collections.abc import Iterable, Mapping
from copy import deepcopy

from tirosh_vitalserver.testkit.types.json import JsonObject, JsonValue


def shift_recorder_payload_time(
    payload: Mapping[str, JsonValue],
    *,
    now: float | None = None,
) -> JsonObject:
    """Copy a recorder payload and shift all known timestamps near `now`.

    Sample recorder payloads contain absolute timestamps. Reusing stale
    timestamps can make a server treat data as old, so load tests should shift
    the payload while preserving relative timing within the sample.
    """

    shifted = deepcopy(dict(payload))
    timestamp_values = list(iter_timestamp_values_for_key(shifted, "dtstart"))
    if not timestamp_values:
        timestamp_values = list(iter_payload_anchor_timestamps(shifted))

    if not timestamp_values:
        return shifted

    target_start = time.time() if now is None else now
    offset = target_start - min(timestamp_values)

    shift_payload_timestamps(shifted, offset)

    return shifted


def iter_timestamp_values_for_key(
    value: JsonValue,
    key_name: str,
) -> Iterable[float]:
    """Yield numeric timestamps for one exact key name."""

    if isinstance(value, dict):
        for key, item in value.items():
            if key == key_name and isinstance(item, int | float):
                yield float(item)
            else:
                yield from iter_timestamp_values_for_key(item, key_name)
    elif isinstance(value, list):
        for item in value:
            yield from iter_timestamp_values_for_key(item, key_name)


def iter_payload_anchor_timestamps(value: JsonValue) -> Iterable[float]:
    """Yield timestamps that can anchor realtime playback."""

    if isinstance(value, dict):
        for key, item in value.items():
            if is_realtime_anchor_key(key) and isinstance(item, int | float):
                yield float(item)
            else:
                yield from iter_payload_anchor_timestamps(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_payload_anchor_timestamps(item)


def is_realtime_anchor_key(key: str) -> bool:
    """Return whether a timestamp key can anchor realtime playback."""

    return key in {"dt", "dtstart", "dtend", "dtserver"}


def shift_payload_timestamps(value: JsonValue, offset: float) -> None:
    """Shift every `dt*` timestamp in-place by one offset."""

    if isinstance(value, dict):
        for key, item in value.items():
            if key.startswith("dt") and isinstance(item, int | float):
                value[key] = float(item) + offset
            else:
                shift_payload_timestamps(item, offset)
    elif isinstance(value, list):
        for item in value:
            shift_payload_timestamps(item, offset)
