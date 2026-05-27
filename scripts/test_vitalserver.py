"""Run common VitalServer productization checks with the testkit CLI."""

from __future__ import annotations

import argparse
import os
import shlex
import shutil
import signal
import subprocess
import sys
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic_settings import BaseSettings, SettingsConfigDict, TomlConfigSettingsSource

from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario

ScenarioName = Literal["health", "smoke", "verify", "load", "stream"]


class StrictConfig(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class ScenarioSelectionConfig(StrictConfig):
    name: ScenarioName = "smoke"


class ServerConfig(StrictConfig):
    base_url: str = "http://localhost"
    timeout: float = Field(default=30, gt=0)
    wait_seconds: float = Field(default=30, gt=0)
    poll_interval_seconds: float = Field(default=1, gt=0)


class BedScenarioConfig(StrictConfig):
    index: int = Field(ge=1)
    scenario: RecorderSignalScenario


class RecorderConfig(StrictConfig):
    payload: Path | None = None
    recorders: int = Field(default=1, ge=1)
    default_scenario: RecorderSignalScenario = RecorderSignalScenario.NORMAL
    beds: tuple[BedScenarioConfig, ...] = ()


class TransferConfig(StrictConfig):
    concurrency: int = Field(default=1, ge=1)
    repeat: int = Field(default=10, ge=1)
    max_failure_rate: float = Field(default=0, ge=0, le=1)


class StreamConfig(StrictConfig):
    interval_seconds: float = Field(default=1, gt=0)
    duration_seconds: float = Field(default=0, ge=0)
    max_messages: int | None = Field(default=None, ge=1)


class VitalServerCheckConfig(BaseSettings):
    """File-backed configuration for VitalServer productization checks."""

    model_config = SettingsConfigDict(extra="forbid", frozen=True)

    scenario: ScenarioSelectionConfig = Field(default_factory=ScenarioSelectionConfig)
    server: ServerConfig = Field(default_factory=ServerConfig)
    recorder: RecorderConfig = Field(default_factory=RecorderConfig)
    transfer: TransferConfig = Field(default_factory=TransferConfig)
    stream: StreamConfig = Field(default_factory=StreamConfig)

    @classmethod
    def from_toml(cls, path: Path) -> VitalServerCheckConfig:
        """Load and validate testkit config from a TOML file."""

        if not path.exists():
            raise FileNotFoundError(f"testkit config file not found: {path}")

        source = TomlConfigSettingsSource(cls, toml_file=path)

        return cls.model_validate(source())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run common VitalServer checks through vitalserver-testkit.",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("config/testkit.toml"),
        help="TOML config file path",
    )
    parser.add_argument(
        "scenario",
        nargs="?",
        choices=["health", "smoke", "verify", "load", "stream"],
        help="Scenario to run. Overrides the config file scenario.",
    )
    args = parser.parse_args(argv)

    config = VitalServerCheckConfig.from_toml(args.config)
    scenario = args.scenario or config.scenario.name
    try:
        run_scenario(scenario, config)
    except KeyboardInterrupt:
        print("\ninterrupted", flush=True)

        return 130
    except subprocess.CalledProcessError as exc:
        if is_process_interrupted(exc.returncode):
            print("\ninterrupted", flush=True)

            return 130

        raise

    return 0


def run_scenario(scenario: ScenarioName, config: VitalServerCheckConfig) -> None:
    if scenario == "health":
        run_health(config)
        return

    if scenario == "verify":
        run_health(config)
        run_verify(config)
        return

    if scenario == "smoke":
        run_health(config)
        run_verify(config)
        run_stream(config, default_max_messages=3)
        return

    if scenario == "load":
        run_health(config)
        run_load(config)
        return

    if scenario == "stream":
        run_health(config)
        run_stream(config)
        return

    raise ValueError(f"unknown scenario: {scenario}")


def run_health(config: VitalServerCheckConfig) -> None:
    run(
        *testkit_command(),
        "health",
        "--vitalserver-url",
        config.server.base_url,
        "--timeout",
        str(config.server.timeout),
        "--wait",
        str(config.server.wait_seconds),
        "--interval",
        str(config.server.poll_interval_seconds),
    )


def run_verify(config: VitalServerCheckConfig) -> None:
    testkit = testkit_command()
    command = [
        *testkit,
        "verify-recorder",
        "--vitalserver-url",
        config.server.base_url,
        "--timeout",
        str(config.server.timeout),
        "--recorders",
        str(config.recorder.recorders),
        "--wait",
        str(config.server.wait_seconds),
        "--interval",
        str(config.server.poll_interval_seconds),
    ]

    insert_payload_argument(command, len(testkit), config.recorder.payload)
    run(*command)


def run_load(config: VitalServerCheckConfig) -> None:
    testkit = testkit_command()
    command = [
        *testkit,
        "send-recorder",
        "--vitalserver-url",
        config.server.base_url,
        "--timeout",
        str(config.server.timeout),
        "--recorders",
        str(config.recorder.recorders),
        "--concurrency",
        str(config.transfer.concurrency),
        "--repeat",
        str(config.transfer.repeat),
        "--max-failure-rate",
        str(config.transfer.max_failure_rate),
    ]

    insert_payload_argument(command, len(testkit), config.recorder.payload)
    run(*command)


def run_stream(
    config: VitalServerCheckConfig,
    *,
    default_max_messages: int | None = None,
) -> None:
    max_messages = config.stream.max_messages
    if max_messages is None:
        max_messages = default_max_messages

    testkit = testkit_command()
    command = [
        *testkit,
        "stream-recorder",
        "--vitalserver-url",
        config.server.base_url,
        "--timeout",
        str(config.server.timeout),
        "--recorders",
        str(config.recorder.recorders),
        "--interval",
        str(config.stream.interval_seconds),
        "--duration",
        str(config.stream.duration_seconds),
        "--default-scenario",
        config.recorder.default_scenario.value,
    ]

    insert_payload_argument(command, len(testkit), config.recorder.payload)

    for bed in config.recorder.beds:
        command.extend(["--bed-scenario", f"{bed.index}={bed.scenario.value}"])

    if max_messages is not None:
        command.extend(["--max-messages", str(max_messages)])

    run(*command)


def insert_payload_argument(
    command: list[str],
    testkit_prefix_length: int,
    payload: Path | None,
) -> None:
    """Insert the optional recorder payload path after the subcommand."""

    if payload is not None:
        command.insert(testkit_prefix_length + 1, str(payload))


def run(*args: str) -> None:
    command = list(args)
    print("\n> " + " ".join(command), flush=True)

    process = subprocess.Popen(command)

    try:
        return_code = process.wait()
    except KeyboardInterrupt:
        stop_process(process)
        raise

    if return_code:
        raise subprocess.CalledProcessError(return_code, command)


def testkit_command() -> list[str]:
    """Return the installed testkit command, with a module fallback."""

    configured = os.environ.get("TESTKIT_CLI")

    if configured:
        return shlex.split(configured)

    if shutil.which("vitalserver-testkit") is not None:
        return ["vitalserver-testkit"]

    return [
        sys.executable,
        "-m",
        "tirosh_vitalserver.testkit.adapters.inbound.cli",
    ]


def stop_process(process: subprocess.Popen[bytes]) -> None:
    """Ask a child process to stop before forcefully killing it."""

    if process.poll() is not None:
        return

    try:
        process.send_signal(signal.SIGINT)
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.terminate()

        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    except ProcessLookupError:
        return


def is_process_interrupted(return_code: int) -> bool:
    """Return whether a process exit code represents Ctrl+C."""

    return return_code in {130, -signal.SIGINT}


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
