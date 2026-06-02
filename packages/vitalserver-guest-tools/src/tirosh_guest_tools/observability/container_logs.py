from __future__ import annotations

import subprocess
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import IO

from tirosh_guest_tools.common import (
    DEPLOY_DIR,
    PROJECT_NAME,
    RUNTIME_DIR,
    mount_runtime_share,
)
from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.domain.operations import ContainerLogAction
from tirosh_guest_tools.settings import SETTINGS

LOG_FILE = RUNTIME_DIR / "container-logs.log"
INTERVAL_SECONDS = SETTINGS.container_logs.interval_seconds
TAIL_LINES = SETTINGS.container_logs.tail_lines
MAX_BYTES = SETTINGS.container_logs.max_bytes
RETAINED_FILES = SETTINGS.container_logs.retained_files
ROTATE_CHECK_LINES = SETTINGS.container_logs.rotate_check_lines


def run_container_log_action(action: ContainerLogAction | str) -> None:
    action = ContainerLogAction(action)
    mount_runtime_share()
    if action == ContainerLogAction.ONCE:
        write_snapshot()
        return
    watch_logs()


def append_marker(source: str) -> None:
    rotate_logs()
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write("\n== container log collector ==\n")
        handle.write(f"updated_at={utc_now()}\n")
        handle.write(f"source={source}\n")


def append_line(line: str) -> None:
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(line)
        handle.write("\n")


def rotate_logs() -> None:
    if not LOG_FILE.is_file():
        return
    if LOG_FILE.stat().st_size < MAX_BYTES:
        return
    for index in range(RETAINED_FILES - 1, 0, -1):
        source = numbered_log(index)
        if source.is_file():
            source.replace(numbered_log(index + 1))
    LOG_FILE.replace(numbered_log(1))


def numbered_log(index: int) -> Path:
    return LOG_FILE.with_name(f"{LOG_FILE.name}.{index}")


def write_snapshot() -> None:
    append_marker(f"docker compose logs --tail={TAIL_LINES}")
    result = subprocess.run(
        docker_compose_logs_command(["--tail", TAIL_LINES]),
        check=False,
        capture_output=True,
        text=True,
    )
    write_stream_lines(result.stdout)
    write_stream_lines(result.stderr)
    if result.returncode != 0:
        append_line(f"collector_error_at={utc_now()}")


def watch_logs() -> None:
    while True:
        append_marker(f"docker compose logs --follow --tail={TAIL_LINES}")
        try:
            with subprocess.Popen(
                docker_compose_logs_command(["--follow", "--tail", TAIL_LINES]),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            ) as process:
                line_count = follow_process_output(process.stdout)
                return_code = process.wait()
                if return_code != 0:
                    append_line(f"collector_error_at={utc_now()}")
                if line_count >= ROTATE_CHECK_LINES:
                    rotate_logs()
        except OSError as error:
            append_line(f"collector_error_at={utc_now()} error={error}")
        append_line(f"collector_reconnect_at={utc_now()}")
        time.sleep(max(INTERVAL_SECONDS, 1.0))


def follow_process_output(stream: IO[str] | None) -> int:
    if stream is None:
        return 0
    line_count = 0
    for line in stream:
        append_line(line.rstrip("\n"))
        line_count += 1
        if line_count >= ROTATE_CHECK_LINES:
            rotate_logs()
            line_count = 0
    return line_count


def write_stream_lines(text: str) -> None:
    for line in text.splitlines():
        append_line(line)


def docker_compose_logs_command(arguments: list[str]) -> list[str]:
    return [
        "docker",
        "compose",
        "--project-name",
        PROJECT_NAME,
        "-f",
        str(DEPLOY_DIR / RuntimeFileName.COMPOSE.value),
        "logs",
        "--no-color",
        *arguments,
    ]


def utc_now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")
