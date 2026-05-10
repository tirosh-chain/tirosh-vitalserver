"""Visibility checks for data accepted by VitalServer."""

from __future__ import annotations

import time
from collections.abc import Mapping

from tirosh_vitalserver.testkit.application.ports import VitalServerPort
from tirosh_vitalserver.testkit.application.results import RecorderVisibilityResult
from tirosh_vitalserver.testkit.domain.recorder.payloads import iter_recorder_rooms
from tirosh_vitalserver.testkit.types.json import JsonValue


def wait_for_recorder_visibility(
    client: VitalServerPort,
    payload: Mapping[str, JsonValue],
    *,
    admin_user_id: str = "admin",
    timeout_seconds: float = 10.0,
    interval_seconds: float = 0.5,
) -> tuple[RecorderVisibilityResult, ...]:
    """Wait until recorder rooms are visible through VitalServer UI APIs."""

    rooms = iter_recorder_rooms(payload, admin_user_id=admin_user_id)
    if not rooms:
        raise ValueError("recorder payload does not contain rooms with roomname")

    deadline = time.monotonic() + timeout_seconds
    latest_results: tuple[RecorderVisibilityResult, ...] = ()

    while time.monotonic() <= deadline:
        latest_results = tuple(
            RecorderVisibilityResult(
                room=room,
                response=client.device_metadata(room.bed_id),
            )
            for room in rooms
        )

        if all(
            _recorder_visibility_result_visible(result) for result in latest_results
        ):
            return latest_results

        time.sleep(interval_seconds)

    missing = ", ".join(
        f"{result.room.room_name}({result.room.bed_id})"
        for result in latest_results
        if not _recorder_visibility_result_visible(result)
    )
    raise TimeoutError(f"recorder rooms were not visible in VitalServer: {missing}")


def _recorder_visibility_result_visible(result: RecorderVisibilityResult) -> bool:
    body = result.response.text.strip()

    return result.response.ok and body not in {"", "{}", "[]", "null"}
