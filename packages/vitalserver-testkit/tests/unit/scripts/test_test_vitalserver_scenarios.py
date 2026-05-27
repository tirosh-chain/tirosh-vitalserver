from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from pydantic import ValidationError
from scripts.test_vitalserver import (
    VitalServerCheckConfig,
    main,
    run,
    run_health,
    run_scenario,
    run_stream,
    run_verify,
)

from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario


def test_testkit_config_loads_toml_file(tmp_path: Path) -> None:
    config_path = tmp_path / "testkit.toml"
    config_path.write_text(
        """
[scenario]
name = "load"

[recorder]
payload = "sample_data.json"
recorders = 5
default_scenario = "normal"

[[recorder.beds]]
index = 2
scenario = "tachycardia"

[server]
base_url = "http://localhost:28080"
poll_interval_seconds = 2

[transfer]
concurrency = 10
repeat = 100
""".strip()
    )

    config = VitalServerCheckConfig.from_toml(config_path)

    assert config.scenario.name == "load"
    assert config.server.base_url == "http://localhost:28080"
    assert config.server.poll_interval_seconds == 2
    assert config.recorder.payload == Path("sample_data.json")
    assert config.recorder.recorders == 5
    assert config.recorder.default_scenario == RecorderSignalScenario.NORMAL
    assert config.recorder.beds[0].index == 2
    assert config.recorder.beds[0].scenario == RecorderSignalScenario.TACHYCARDIA
    assert config.transfer.concurrency == 10
    assert config.transfer.repeat == 100


def test_testkit_config_rejects_invalid_values(tmp_path: Path) -> None:
    config_path = tmp_path / "testkit.toml"
    config_path.write_text("[recorder]\nrecorders = 0")

    with pytest.raises(ValidationError):
        VitalServerCheckConfig.from_toml(config_path)


def test_run_scenario_uses_requested_scenario(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = VitalServerCheckConfig()
    calls: list[str] = []

    monkeypatch.setattr(
        "scripts.test_vitalserver.run_health",
        lambda config: calls.append("health"),
    )
    monkeypatch.setattr(
        "scripts.test_vitalserver.run_load",
        lambda config: calls.append("load"),
    )

    run_scenario("load", config)

    assert calls == ["health", "load"]


def test_run_health_uses_server_poll_interval(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = VitalServerCheckConfig()
    commands: list[tuple[str, ...]] = []

    monkeypatch.setattr(
        "scripts.test_vitalserver.run",
        lambda *args: commands.append(args),
    )

    run_health(config)

    assert "--interval" in commands[0]
    interval_index = commands[0].index("--interval")
    assert commands[0][interval_index + 1] == str(config.server.poll_interval_seconds)


def test_run_verify_omits_payload_argument_by_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = VitalServerCheckConfig()
    commands: list[tuple[str, ...]] = []

    monkeypatch.setenv("TESTKIT_CLI", "vitalserver-testkit")
    monkeypatch.setattr(
        "scripts.test_vitalserver.run",
        lambda *args: commands.append(args),
    )

    run_verify(config)

    assert commands[0][:2] == ("vitalserver-testkit", "verify-recorder")
    assert commands[0][2] == "--vitalserver-url"


def test_run_verify_inserts_configured_payload_argument(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = VitalServerCheckConfig.model_validate(
        {"recorder": {"payload": "sample_data.json"}}
    )
    commands: list[tuple[str, ...]] = []

    monkeypatch.setenv("TESTKIT_CLI", "vitalserver-testkit")
    monkeypatch.setattr(
        "scripts.test_vitalserver.run",
        lambda *args: commands.append(args),
    )

    run_verify(config)

    assert commands[0][:3] == (
        "vitalserver-testkit",
        "verify-recorder",
        "sample_data.json",
    )


def test_run_verify_inserts_payload_after_fallback_module_subcommand(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = VitalServerCheckConfig.model_validate(
        {"recorder": {"payload": "sample_data.json"}}
    )
    commands: list[tuple[str, ...]] = []

    monkeypatch.delenv("TESTKIT_CLI", raising=False)
    monkeypatch.setattr("scripts.test_vitalserver.shutil.which", lambda _: None)
    monkeypatch.setattr(
        "scripts.test_vitalserver.run",
        lambda *args: commands.append(args),
    )

    run_verify(config)

    subcommand_index = commands[0].index("verify-recorder")
    assert commands[0][subcommand_index + 1] == "sample_data.json"


def test_run_stream_passes_bed_scenario_overrides(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    config = VitalServerCheckConfig.model_validate(
        {
            "recorder": {
                "recorders": 3,
                "default_scenario": "normal",
                "beds": [{"index": 2, "scenario": "tachycardia"}],
            }
        }
    )
    commands: list[tuple[str, ...]] = []

    monkeypatch.setattr(
        "scripts.test_vitalserver.run",
        lambda *args: commands.append(args),
    )

    run_stream(config)

    assert "--default-scenario" in commands[0]
    assert commands[0][commands[0].index("--default-scenario") + 1] == "normal"
    assert "--bed-scenario" in commands[0]
    assert commands[0][commands[0].index("--bed-scenario") + 1] == "2=tachycardia"


def test_run_executes_installed_testkit_command(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    commands: list[list[str]] = []

    class FakeProcess:
        def __init__(self, command: list[str]) -> None:
            commands.append(command)

        def wait(self, timeout: float | None = None) -> int:
            return 0

        def poll(self) -> int | None:
            return 0

    monkeypatch.setattr("scripts.test_vitalserver.subprocess.Popen", FakeProcess)

    run("vitalserver-testkit", "health")

    assert commands == [["vitalserver-testkit", "health"]]


def test_run_raises_for_failed_testkit_command(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class FakeProcess:
        def __init__(self, command: list[str]) -> None:
            self.command = command

        def wait(self, timeout: float | None = None) -> int:
            return 1

        def poll(self) -> int | None:
            return 1

    monkeypatch.setattr("scripts.test_vitalserver.subprocess.Popen", FakeProcess)

    with pytest.raises(subprocess.CalledProcessError):
        run("vitalserver-testkit", "health")


def test_main_returns_130_for_keyboard_interrupt(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "scripts.test_vitalserver.run_scenario",
        lambda scenario, config: (_ for _ in ()).throw(KeyboardInterrupt),
    )

    assert main(["stream"]) == 130
