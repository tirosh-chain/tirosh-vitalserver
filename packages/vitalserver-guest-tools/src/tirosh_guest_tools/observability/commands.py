from __future__ import annotations

import subprocess
from collections.abc import Sequence
from dataclasses import dataclass


@dataclass(frozen=True)
class CommandResult:
    command: str
    exit_code: int | None
    stdout: str
    stderr: str
    timed_out: bool

    def as_dict(self) -> dict[str, object]:
        return {
            "command": self.command,
            "exitCode": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "timedOut": self.timed_out,
        }


def run_command(argv: Sequence[str], *, timeout_seconds: float = 3.0) -> CommandResult:
    command = " ".join(argv)
    try:
        completed = subprocess.run(
            list(argv),
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
        return CommandResult(
            command=command,
            exit_code=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
            timed_out=False,
        )
    except subprocess.TimeoutExpired as error:
        return CommandResult(
            command=command,
            exit_code=None,
            stdout=output_text(error.stdout),
            stderr=output_text(error.stderr),
            timed_out=True,
        )
    except OSError as error:
        return CommandResult(
            command=command,
            exit_code=None,
            stdout="",
            stderr=str(error),
            timed_out=False,
        )


def run_shell(script: str, *, timeout_seconds: float = 3.0) -> CommandResult:
    return run_command(["/bin/bash", "-lc", script], timeout_seconds=timeout_seconds)


def output_text(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode(errors="replace")
    return value
