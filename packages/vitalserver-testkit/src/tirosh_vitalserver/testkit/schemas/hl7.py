"""Typed contract produced from the legacy VitalServer HL7 response."""

from __future__ import annotations

from tirosh_vitalserver.testkit.schemas.base import ExternalSchema


class Hl7Observation(ExternalSchema):
    """One OBX observation without interpreting or defaulting its value."""

    value_type: str
    identifier: str
    sub_id: str
    value: str
    unit: str
    status: str


class Hl7Message(ExternalSchema):
    """One bed-level ORU message emitted by the legacy VitalServer endpoint."""

    version: str
    patient_id: str
    group: str
    bed_name: str
    observed_at: str
    observations: tuple[Hl7Observation, ...]
