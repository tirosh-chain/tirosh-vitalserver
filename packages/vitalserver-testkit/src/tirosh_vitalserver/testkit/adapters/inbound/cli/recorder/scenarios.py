"""CLI parsing helpers for recorder signal scenarios."""

from __future__ import annotations

import argparse

from tirosh_vitalserver.testkit.domain.signal import (
    RecorderSignalScenario,
    SignalProfile,
    profile_for_scenario,
)


def parse_bed_signal_profiles(values: list[str]) -> dict[int, SignalProfile]:
    """Parse `INDEX=SCENARIO` CLI values into bed-specific signal profiles."""

    profiles = {}

    for value in values:
        index_text, separator, scenario_text = value.partition("=")
        if not separator:
            raise argparse.ArgumentTypeError(
                f"bed scenario must be INDEX=SCENARIO: {value}"
            )

        index = parse_bed_index(index_text)
        scenario = parse_recorder_signal_scenario(scenario_text)
        profiles[index] = profile_for_scenario(scenario)

    return profiles


def parse_bed_index(value: str) -> int:
    """Parse a 1-based bed index from CLI text."""

    try:
        index = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"bed scenario index must be an integer: {value}"
        ) from exc

    if index < 1:
        raise argparse.ArgumentTypeError(
            f"bed scenario index must be greater than 0: {index}"
        )

    return index


def parse_recorder_signal_scenario(value: str) -> RecorderSignalScenario:
    """Parse a signal scenario name from CLI text."""

    try:
        return RecorderSignalScenario(value)
    except ValueError as exc:
        allowed = ", ".join(scenario.value for scenario in RecorderSignalScenario)
        raise argparse.ArgumentTypeError(
            f"unknown signal scenario: {value}. allowed: {allowed}"
        ) from exc
