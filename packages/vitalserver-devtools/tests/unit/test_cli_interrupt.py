from __future__ import annotations

from tirosh_vitalserver.devtools import cli


def test_main_reports_keyboard_interrupt_without_traceback(monkeypatch, capsys):
    def interrupt(_input):
        raise KeyboardInterrupt

    monkeypatch.setattr(
        cli.build_config_usecases,
        "print_config_value",
        interrupt,
    )
    monkeypatch.setattr(
        "sys.argv",
        ["vitalserver-devtools", "config-value", "guest.docker_images.bundle_path"],
    )

    assert cli.main() == 130

    captured = capsys.readouterr()
    assert "interrupted by user while running vitalserver-devtools" in captured.err
    assert "Traceback" not in captured.err
