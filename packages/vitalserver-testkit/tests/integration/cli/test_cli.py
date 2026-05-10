from __future__ import annotations

import pytest

from tirosh_vitalserver.testkit.adapters.inbound.cli.__main__ import main


def test_cli_help_returns_usage(capsys: pytest.CaptureFixture[str]) -> None:
    exit_code = main([])

    captured = capsys.readouterr()
    assert exit_code == 2
    assert "usage: vitalserver-testkit" in captured.out


def test_cli_subcommand_help(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc_info:
        main(["send-recorder", "--help"])

    captured = capsys.readouterr()
    assert exc_info.value.code == 0
    assert "sample_data.json" not in captured.out
    assert "payload" in captured.out
    assert "Socket.IO" in captured.out
