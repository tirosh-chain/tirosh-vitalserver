"""Purpose-centered recorder test scenario catalog."""

from __future__ import annotations

import os
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from tirosh_vitalserver.testkit.application.recorder_session.models import (
    RecorderScenarioWindow,
    RecorderTestScenario,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.real_vital_sample import (
    RealVitalSampleScenario,
)
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario

SCENARIO_DATA_DIR_ENV = "VITALSERVER_TESTKIT_SCENARIO_DATA_DIR"


class RecorderScenarioProvider(StrEnum):
    """Internal provider used to build one scenario payload."""

    GENERATED_PROFILE = "generated_profile"
    VITAL_FILE_WINDOW = "vital_file_window"


@dataclass(frozen=True)
class RecorderScenarioDefinition:
    """Explicit definition of one Test tab scenario."""

    scenario: RecorderTestScenario
    title: str
    situation: str
    purpose: str
    default_bedroom_name: str
    default_window: RecorderScenarioWindow | None
    tracks: tuple[str, ...]
    provider: RecorderScenarioProvider
    signal_profile: RecorderSignalScenario | None = None
    source_path: Path | None = None
    source_scenario: RealVitalSampleScenario | None = None

    def __post_init__(self) -> None:
        """Validate provider-specific scenario contracts."""

        if self.provider == RecorderScenarioProvider.GENERATED_PROFILE:
            if self.signal_profile is None:
                raise ValueError("generated scenario requires signal_profile")
            if self.source_path is not None or self.source_scenario is not None:
                raise ValueError(
                    "generated scenario must not declare vital source fields"
                )
        if self.provider == RecorderScenarioProvider.VITAL_FILE_WINDOW:
            if self.source_path is None:
                raise ValueError("vital-file scenario requires source_path")
            if self.source_scenario is None:
                raise ValueError("vital-file scenario requires source_scenario")
            if self.signal_profile is not None:
                raise ValueError(
                    "vital-file scenario must not declare signal_profile"
                )


def default_scenario_catalog(
    data_dir: Path | None = None,
) -> tuple[RecorderScenarioDefinition, ...]:
    """Return the built-in TestKit scenario catalog."""

    root = data_dir or Path(os.environ.get(SCENARIO_DATA_DIR_ENV, "data"))

    return (
        generated_scenario(
            RecorderTestScenario.NORMAL_MONITORING,
            title="Normal monitoring",
            situation=(
                "Basic ECG, plethysmograph, arterial pressure, CO2, and vital "
                "numeric data are streamed from a stable recorder."
            ),
            purpose=(
                "Verify ordinary hot-path ingestion, recorder visibility, and "
                "baseline .vital export."
            ),
            tracks=("ECG", "PLETH", "ART", "CO2", "HR", "PLETH_SPO2"),
            signal_profile=RecorderSignalScenario.NORMAL,
        ),
        generated_scenario(
            RecorderTestScenario.TACHYCARDIA,
            title="Tachycardia",
            situation=(
                "A stable recorder sends faster ECG rhythm and elevated "
                "heart-rate numeric data."
            ),
            purpose="Verify changing numeric trend and denser waveform frame handling.",
            tracks=("ECG", "HR", "PLETH", "PLETH_SPO2"),
            signal_profile=RecorderSignalScenario.TACHYCARDIA,
        ),
        generated_scenario(
            RecorderTestScenario.DESATURATION,
            title="Desaturation",
            situation=(
                "Pulse oxygen saturation is lower while plethysmograph data "
                "remains active."
            ),
            purpose=(
                "Verify SpO2 trend delivery, display, replay, and .vital "
                "preservation."
            ),
            tracks=("PLETH", "PLETH_SPO2", "HR"),
            signal_profile=RecorderSignalScenario.DESATURATION,
        ),
        generated_scenario(
            RecorderTestScenario.SIGNAL_ARTIFACT,
            title="Signal artifact",
            situation="Waveform samples include noisy and distorted segments.",
            purpose=(
                "Verify ingress, replay, and export resilience when waveform "
                "quality is poor."
            ),
            tracks=("ECG", "PLETH", "ART"),
            signal_profile=RecorderSignalScenario.ARTIFACT,
        ),
        generated_scenario(
            RecorderTestScenario.DEVICE_DISCONNECT,
            title="Device disconnect",
            situation=(
                "The recorder remains present but monitored values drop to "
                "disconnected signal states."
            ),
            purpose=(
                "Verify stale/disconnected signal handling without hiding "
                "partial data."
            ),
            tracks=("ECG", "PLETH", "HR", "PLETH_SPO2"),
            signal_profile=RecorderSignalScenario.DEVICE_DISCONNECT,
        ),
        generated_scenario(
            RecorderTestScenario.HCT_DECREASING,
            title="HCT decreasing",
            situation=(
                "Hematocrit decreases gradually while ordinary monitoring "
                "continues."
            ),
            purpose=(
                "Verify HCT numeric generation, streaming, replay, and .vital "
                "export."
            ),
            tracks=("ECG", "PLETH", "HCT"),
            signal_profile=RecorderSignalScenario.HCT_DECREASING,
        ),
        vital_file_scenario(
            RecorderTestScenario.BLOODBAG_TRANSFUSION,
            title="Bloodbag transfusion",
            situation=(
                "Bloodbag-related SpHb, plethysmograph, and derived HCT data "
                "are replayed together."
            ),
            purpose=(
                "Verify blood-related tracks remain intact through hot path, "
                "cold path, and .vital export."
            ),
            tracks=("Root/SPHB", "Root/PLETH", "LabDerived/HCT"),
            source_path=root / "MORC03_230102" / "MORC03_230102_133133.vital",
            source_scenario=RealVitalSampleScenario.BLOODBAG,
            default_window=RecorderScenarioWindow(
                start_offset_seconds=70,
                duration_seconds=20,
            ),
        ),
        vital_file_scenario(
            RecorderTestScenario.PERIOPERATIVE_MONITORING,
            title="Perioperative monitoring",
            situation=(
                "Multi-device operating-room data includes ECG, arterial "
                "pressure, CO2, and anesthesia-related tracks."
            ),
            purpose="Verify high-track-count payload handling and export completeness.",
            tracks=("Bx50/ECG_II", "Bx50/ART", "Primus/CO2", "Primus/ETCO2"),
            source_path=root / "MORA04_230102" / "MORA04_230102_110306.vital",
            source_scenario=RealVitalSampleScenario.PERIOP_FULL,
            default_window=RecorderScenarioWindow(
                start_offset_seconds=0,
                duration_seconds=20,
            ),
        ),
        vital_file_scenario(
            RecorderTestScenario.SEDATION_MONITORING,
            title="Sedation monitoring",
            situation=(
                "Root device oximetry and sedation-adjacent monitoring tracks "
                "are replayed."
            ),
            purpose=(
                "Verify Root-device track mapping and mixed numeric/waveform "
                "handling."
            ),
            tracks=("Root/PLETH", "Root/SPHB", "Root/SPO2"),
            source_path=root / "MORC03_230102" / "MORC03_230102_133133.vital",
            source_scenario=RealVitalSampleScenario.ROOT_SEDATION,
            default_window=RecorderScenarioWindow(
                start_offset_seconds=70,
                duration_seconds=20,
            ),
        ),
        vital_file_scenario(
            RecorderTestScenario.FULL_MONITORING_REPLAY,
            title="Full monitoring replay",
            situation=(
                "The available real recorder tracks from a source file are "
                "replayed together."
            ),
            purpose=(
                "Verify broad mixed-track replay, export performance, and "
                "missing-track visibility."
            ),
            tracks=("all available source tracks",),
            source_path=root / "MORA04_230102" / "MORA04_230102_110306.vital",
            source_scenario=RealVitalSampleScenario.FULL_REAL,
            default_window=RecorderScenarioWindow(
                start_offset_seconds=0,
                duration_seconds=20,
            ),
        ),
    )


def require_scenario_definition(
    scenario: RecorderTestScenario,
    *,
    catalog: tuple[RecorderScenarioDefinition, ...] | None = None,
) -> RecorderScenarioDefinition:
    """Return the explicit definition for one scenario."""

    definitions = catalog or default_scenario_catalog()
    for definition in definitions:
        if definition.scenario == scenario:
            return definition
    raise ValueError(f"unknown recorder test scenario: {scenario.value}")


def scenario_window_for_request(
    request_window: RecorderScenarioWindow | None,
    definition: RecorderScenarioDefinition,
) -> RecorderScenarioWindow | None:
    """Return the effective window without inventing hidden scenario state."""

    if request_window is None:
        return definition.default_window
    if definition.default_window is None:
        return request_window
    return RecorderScenarioWindow(
        start_offset_seconds=(
            request_window.start_offset_seconds
            if request_window.start_offset_seconds is not None
            else definition.default_window.start_offset_seconds
        ),
        duration_seconds=(
            request_window.duration_seconds
            if request_window.duration_seconds is not None
            else definition.default_window.duration_seconds
        ),
    )


def generated_scenario(
    scenario: RecorderTestScenario,
    *,
    title: str,
    situation: str,
    purpose: str,
    tracks: tuple[str, ...],
    signal_profile: RecorderSignalScenario,
) -> RecorderScenarioDefinition:
    """Create a generated-profile scenario definition."""

    return RecorderScenarioDefinition(
        scenario=scenario,
        title=title,
        situation=situation,
        purpose=purpose,
        default_bedroom_name="TestBedroom",
        default_window=None,
        tracks=tracks,
        provider=RecorderScenarioProvider.GENERATED_PROFILE,
        signal_profile=signal_profile,
    )


def vital_file_scenario(
    scenario: RecorderTestScenario,
    *,
    title: str,
    situation: str,
    purpose: str,
    tracks: tuple[str, ...],
    source_path: Path,
    source_scenario: RealVitalSampleScenario,
    default_window: RecorderScenarioWindow,
) -> RecorderScenarioDefinition:
    """Create a vital-file-backed scenario definition."""

    return RecorderScenarioDefinition(
        scenario=scenario,
        title=title,
        situation=situation,
        purpose=purpose,
        default_bedroom_name="TestBedroom",
        default_window=default_window,
        tracks=tracks,
        provider=RecorderScenarioProvider.VITAL_FILE_WINDOW,
        source_path=source_path,
        source_scenario=source_scenario,
    )


def scenario_definition_to_document(
    definition: RecorderScenarioDefinition,
) -> dict[str, object]:
    """Return the public API document for one scenario definition."""

    window = definition.default_window
    return {
        "scenario": definition.scenario.value,
        "title": definition.title,
        "situation": definition.situation,
        "purpose": definition.purpose,
        "defaultBedroomName": definition.default_bedroom_name,
        "defaultWindow": None
        if window is None
        else {
            "startOffsetSeconds": window.start_offset_seconds,
            "durationSeconds": window.duration_seconds,
        },
        "tracks": list(definition.tracks),
    }
