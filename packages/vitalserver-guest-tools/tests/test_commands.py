from __future__ import annotations

from tirosh_guest_tools.adapters.outbound.observability.commands import run_command


def test_run_command_reports_missing_command_as_failure() -> None:
    result = run_command(["/definitely/missing/tirosh-command"])

    assert result.exit_code is None
    assert result.stderr
    assert result.timed_out is False
