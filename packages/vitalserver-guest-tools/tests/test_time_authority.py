from __future__ import annotations

import json
import subprocess
from datetime import UTC, datetime
from pathlib import Path

import pytest

from tirosh_guest_tools.domain.time_authority import (
    TimeAuthorityContractError,
    chrony_configuration,
    parse_chrony_tracking,
    parse_time_authority,
)
from tirosh_guest_tools.infrastructure import time_authority


def authority_document(**overrides: object) -> dict[str, object]:
    document: dict[str, object] = {
        "schemaVersion": 1,
        "profile": "helper-ntp",
        "sourceId": "helper-host-clock",
        "serverAddress": "192.168.64.1",
        "serverPort": 123,
        "state": "host-clock-only",
        "stratum": 10,
        "allowedClientAddress": "192.168.64.3",
        "updatedAt": "2026-07-28T07:25:32Z",
    }
    document.update(overrides)
    return document


def test_time_authority_requires_explicit_usable_host_state() -> None:
    with pytest.raises(TimeAuthorityContractError, match="not usable"):
        parse_time_authority(authority_document(state="failed"))


def test_chrony_configuration_uses_only_contract_server() -> None:
    authority = parse_time_authority(authority_document())

    assert chrony_configuration(authority) == (
        "# Managed by Tirosh VitalServer Guest Tools.\n"
        "# source-id: helper-host-clock\n"
        "server 192.168.64.1 port 123 iburst\n"
        "driftfile /var/lib/chrony/chrony.drift\n"
        "makestep 0.1 3\n"
        "rtcsync\n"
        "logdir /var/log/chrony\n"
    )


def test_apply_time_authority_writes_atomically_and_restarts_chrony(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    contract = tmp_path / "time-authority.json"
    configuration = tmp_path / "chrony.conf"
    contract.write_text(json.dumps(authority_document()), encoding="utf-8")
    commands: list[list[str]] = []
    monkeypatch.setattr(
        time_authority.subprocess,
        "run",
        lambda command, check: commands.append(command),
    )

    time_authority.apply_time_authority(
        contract_path=contract,
        configuration_path=configuration,
    )

    assert "server 192.168.64.1 port 123 iburst" in configuration.read_text()
    assert commands == [["systemctl", "restart", "chrony.service"]]

    time_authority.apply_time_authority(
        contract_path=contract,
        configuration_path=configuration,
    )

    assert commands == [["systemctl", "restart", "chrony.service"]]


def test_parse_chrony_tracking_requires_complete_synchronization_evidence() -> None:
    observed_at = datetime(2026, 7, 28, 7, 25, 32, tzinfo=UTC)

    quality = parse_chrony_tracking(
        "\n".join(
            [
                "Reference ID    : C0A84001 (192.168.64.1)",
                "Stratum         : 11",
                "Ref time (UTC)  : Tue Jul 28 07:25:31 2026",
                "System time     : 0.000250000 seconds slow of NTP time",
                "Root delay      : 0.000100000 seconds",
                "Root dispersion : 0.000800000 seconds",
                "Leap status     : Normal",
            ]
        ),
        observed_at,
    )

    assert quality.state == "synchronized"
    assert quality.source == "192.168.64.1"
    assert quality.stratum == 11
    assert quality.offset_ms == pytest.approx(-0.25)
    assert quality.uncertainty_ms == pytest.approx(0.8)
    assert quality.root_dispersion_ms == pytest.approx(0.8)
    assert quality.last_sync_at == "2026-07-28T07:25:31+00:00"


def test_parse_chrony_tracking_preserves_unsynchronized_state() -> None:
    quality = parse_chrony_tracking(
        "Leap status : Not synchronised",
        datetime(2026, 7, 28, tzinfo=UTC),
    )

    assert quality.state == "unsynchronized"
    assert quality.issue == "chrony leap status is Not synchronised"


def test_read_clock_quality_preserves_command_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        time_authority.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args[0],
            1,
            stdout="",
            stderr="506 Cannot talk to daemon",
        ),
    )

    quality = time_authority.read_clock_quality(
        now=datetime(2026, 7, 28, tzinfo=UTC)
    )

    assert quality.state == "failed"
    assert "506 Cannot talk to daemon" in (quality.issue or "")


def test_read_clock_quality_reports_missing_chrony_as_unsupported(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def missing(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
        raise FileNotFoundError("chronyc")

    monkeypatch.setattr(time_authority.subprocess, "run", missing)

    quality = time_authority.read_clock_quality(
        now=datetime(2026, 7, 28, tzinfo=UTC)
    )

    assert quality.state == "unsupported"
    assert quality.issue == "chronyc executable is unavailable"
