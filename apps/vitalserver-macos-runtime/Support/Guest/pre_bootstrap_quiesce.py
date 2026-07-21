#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from collections.abc import Callable
from dataclasses import dataclass

CONSUMER_UNITS = (
    "tirosh-runtime-observation.service",
    "tirosh-vitalserver-container-logs.service",
    "tirosh-vitalserver-compose.service",
)
COMMAND_TIMEOUT_SECONDS = 30.0


@dataclass(frozen=True)
class ConsumerQuiesceState:
    load_state: str
    active_state: str | None


def read_unit_property(
    unit: str,
    property_name: str,
    *,
    run: Callable[..., subprocess.CompletedProcess[str]],
) -> str:
    try:
        completed = run(
            [
                "systemctl",
                "show",
                f"--property={property_name}",
                "--value",
                unit,
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(
            "pre-bootstrap consumer property read timed out: "
            f"unit={unit} property={property_name} "
            f"timeoutSeconds={COMMAND_TIMEOUT_SECONDS:g}"
        ) from error
    if completed.returncode != 0:
        raise RuntimeError(
            "pre-bootstrap consumer property read failed: "
            f"unit={unit} property={property_name} exit={completed.returncode} "
            f"stdout={completed.stdout} stderr={completed.stderr}"
        )
    value = completed.stdout.strip()
    if not value or "\n" in value:
        raise RuntimeError(
            "pre-bootstrap consumer property is invalid: "
            f"unit={unit} property={property_name} value={value!r}"
        )
    return value


def request_consumer_stop(
    *,
    run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> dict[str, ConsumerQuiesceState]:
    load_states = {
        unit: read_unit_property(unit, "LoadState", run=run)
        for unit in CONSUMER_UNITS
    }
    existing_units = tuple(
        unit for unit, load_state in load_states.items() if load_state != "not-found"
    )
    if not existing_units:
        return {
            unit: ConsumerQuiesceState(load_state=load_state, active_state=None)
            for unit, load_state in load_states.items()
        }

    arguments = ["systemctl", "stop", "--no-block", *existing_units]
    try:
        completed = run(
            arguments,
            check=False,
            capture_output=True,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(
            "pre-bootstrap consumer stop request timed out: "
            f"units={','.join(existing_units)} "
            f"timeoutSeconds={COMMAND_TIMEOUT_SECONDS:g}"
        ) from error
    if completed.returncode != 0:
        raise RuntimeError(
            "pre-bootstrap consumer stop request failed: "
            f"units={','.join(existing_units)} exit={completed.returncode} "
            f"stdout={completed.stdout} stderr={completed.stderr}"
        )

    states: dict[str, ConsumerQuiesceState] = {}
    for unit in CONSUMER_UNITS:
        load_state = load_states[unit]
        if load_state == "not-found":
            states[unit] = ConsumerQuiesceState(
                load_state=load_state,
                active_state=None,
            )
            continue
        active_state = read_unit_property(unit, "ActiveState", run=run)
        states[unit] = ConsumerQuiesceState(
            load_state=load_state,
            active_state=active_state,
        )
    return states


def main() -> int:
    states = request_consumer_stop()
    print(
        "Pre-bootstrap consumer stop requested: "
        + ",".join(
            f"{unit}=load:{state.load_state}/active:{state.active_state}"
            for unit, state in states.items()
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
