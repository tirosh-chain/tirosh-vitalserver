from __future__ import annotations

import ipaddress
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any


class TimeAuthorityContractError(ValueError):
    pass


@dataclass(frozen=True)
class TimeAuthority:
    profile: str
    source_id: str
    server_address: str
    server_port: int
    host_state: str
    host_stratum: int
    updated_at: str


@dataclass(frozen=True)
class ClockQuality:
    state: str
    observed_at: datetime
    source: str | None = None
    stratum: int | None = None
    offset_ms: float | None = None
    uncertainty_ms: float | None = None
    root_delay_ms: float | None = None
    root_dispersion_ms: float | None = None
    last_sync_at: str | None = None
    issue: str | None = None

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "state": self.state,
            "observedAt": self.observed_at.isoformat(),
        }
        for key, value in (
            ("source", self.source),
            ("stratum", self.stratum),
            ("offsetMs", self.offset_ms),
            ("uncertaintyMs", self.uncertainty_ms),
            ("rootDelayMs", self.root_delay_ms),
            ("rootDispersionMs", self.root_dispersion_ms),
            ("lastSyncAt", self.last_sync_at),
            ("issue", self.issue),
        ):
            if value is not None:
                document[key] = value
        return document


def parse_time_authority(document: object) -> TimeAuthority:
    if not isinstance(document, dict):
        raise TimeAuthorityContractError("time authority contract must be an object")
    if document.get("schemaVersion") != 1:
        raise TimeAuthorityContractError(
            "time authority schemaVersion must be 1"
        )
    profile = required_string(document, "profile")
    if profile not in {"helper-ntp", "enterprise-ntp"}:
        raise TimeAuthorityContractError(
            f"time authority profile is unsupported: {profile}"
        )
    host_state = required_string(document, "state")
    if host_state not in {"synchronized", "host-clock-only"}:
        raise TimeAuthorityContractError(
            f"time authority is not usable: state={host_state}"
        )
    source_id = required_string(document, "sourceId")
    server_address = required_string(document, "serverAddress")
    try:
        ipaddress.ip_address(server_address)
    except ValueError as error:
        raise TimeAuthorityContractError(
            f"time authority serverAddress is invalid: {server_address}"
        ) from error
    server_port = document.get("serverPort")
    if (
        not isinstance(server_port, int)
        or isinstance(server_port, bool)
        or not 1 <= server_port <= 65535
    ):
        raise TimeAuthorityContractError(
            "time authority serverPort must be an integer from 1 through 65535"
        )
    host_stratum = document.get("stratum")
    if (
        not isinstance(host_stratum, int)
        or isinstance(host_stratum, bool)
        or not 1 <= host_stratum <= 15
    ):
        raise TimeAuthorityContractError(
            "time authority stratum must be an integer from 1 through 15"
        )
    updated_at = required_string(document, "updatedAt")
    return TimeAuthority(
        profile=profile,
        source_id=source_id,
        server_address=server_address,
        server_port=server_port,
        host_state=host_state,
        host_stratum=host_stratum,
        updated_at=updated_at,
    )


def chrony_configuration(authority: TimeAuthority) -> str:
    return (
        "# Managed by Tirosh VitalServer Guest Tools.\n"
        f"# source-id: {authority.source_id}\n"
        f"server {authority.server_address} port {authority.server_port} iburst\n"
        "driftfile /var/lib/chrony/chrony.drift\n"
        "makestep 0.1 3\n"
        "rtcsync\n"
        "logdir /var/log/chrony\n"
    )


def parse_chrony_tracking(output: str, observed_at: datetime) -> ClockQuality:
    fields: dict[str, str] = {}
    for line in output.splitlines():
        name, separator, value = line.partition(":")
        if separator:
            fields[name.strip()] = value.strip()
    leap_status = fields.get("Leap status")
    if leap_status is None:
        raise ValueError("chronyc tracking output is missing Leap status")
    if leap_status != "Normal":
        return ClockQuality(
            state="unsynchronized",
            observed_at=observed_at,
            issue=f"chrony leap status is {leap_status}",
        )

    source = tracking_source(fields.get("Reference ID"))
    stratum = tracking_integer(fields, "Stratum", minimum=1, maximum=15)
    offset_ms = tracking_system_offset_ms(fields.get("System time"))
    root_delay_ms = tracking_seconds_ms(fields, "Root delay")
    root_dispersion_ms = tracking_seconds_ms(fields, "Root dispersion")
    last_sync_text = fields.get("Ref time (UTC)")
    if not last_sync_text:
        raise ValueError("chronyc tracking output is missing Ref time (UTC)")
    try:
        last_sync_at = (
            datetime.strptime(last_sync_text, "%a %b %d %H:%M:%S %Y")
            .replace(tzinfo=UTC)
            .isoformat()
        )
    except ValueError as error:
        raise ValueError(
            f"chronyc tracking Ref time (UTC) is invalid: {last_sync_text}"
        ) from error
    return ClockQuality(
        state="synchronized",
        observed_at=observed_at,
        source=source,
        stratum=stratum,
        offset_ms=offset_ms,
        uncertainty_ms=root_dispersion_ms,
        root_delay_ms=root_delay_ms,
        root_dispersion_ms=root_dispersion_ms,
        last_sync_at=last_sync_at,
    )


def required_string(document: dict[str, Any], key: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value.strip():
        raise TimeAuthorityContractError(
            f"time authority {key} must be a non-empty string"
        )
    return value.strip()


def tracking_source(value: str | None) -> str:
    if not value:
        raise ValueError("chronyc tracking output is missing Reference ID")
    match = re.fullmatch(r"\S+\s+\(([^)]+)\)", value)
    return match.group(1) if match else value


def tracking_integer(
    fields: dict[str, str],
    key: str,
    *,
    minimum: int,
    maximum: int,
) -> int:
    value = fields.get(key)
    try:
        parsed = int(value or "")
    except ValueError as error:
        raise ValueError(f"chronyc tracking {key} is invalid: {value}") from error
    if not minimum <= parsed <= maximum:
        raise ValueError(f"chronyc tracking {key} is out of range: {parsed}")
    return parsed


def tracking_seconds_ms(fields: dict[str, str], key: str) -> float:
    value = fields.get(key)
    match = re.fullmatch(r"([+-]?\d+(?:\.\d+)?) seconds", value or "")
    if match is None:
        raise ValueError(f"chronyc tracking {key} is invalid: {value}")
    return float(match.group(1)) * 1000


def tracking_system_offset_ms(value: str | None) -> float:
    match = re.fullmatch(
        r"(\d+(?:\.\d+)?) seconds (fast|slow) of NTP time",
        value or "",
    )
    if match is None:
        raise ValueError(f"chronyc tracking System time is invalid: {value}")
    magnitude = float(match.group(1)) * 1000
    return magnitude if match.group(2) == "fast" else -magnitude
