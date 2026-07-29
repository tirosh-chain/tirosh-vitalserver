from __future__ import annotations

import json
import os
import subprocess
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from tirosh_guest_tools.domain.time_authority import (
    ClockQuality,
    chrony_configuration,
    parse_chrony_tracking,
    parse_time_authority,
)

TIME_AUTHORITY_CONTRACT = Path("/mnt/tirosh/deploy/time-authority.json")
CHRONY_CONFIGURATION = Path("/etc/chrony/chrony.conf")


def apply_time_authority(
    *,
    contract_path: Path = TIME_AUTHORITY_CONTRACT,
    configuration_path: Path = CHRONY_CONFIGURATION,
) -> None:
    try:
        document = json.loads(contract_path.read_text(encoding="utf-8"))
    except OSError as error:
        raise RuntimeError(
            f"time authority contract is unreadable: {contract_path}: {error}"
        ) from error
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"time authority contract is invalid JSON: {contract_path}: {error}"
        ) from error
    authority = parse_time_authority(document)
    changed = write_text_atomic(
        configuration_path,
        chrony_configuration(authority),
    )
    if changed:
        subprocess.run(["systemctl", "restart", "chrony.service"], check=True)


def read_clock_quality(
    *,
    now: datetime | None = None,
) -> ClockQuality:
    observed_at = now or datetime.now(UTC)
    try:
        completed = subprocess.run(
            ["chronyc", "tracking", "-n"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except FileNotFoundError:
        return ClockQuality(
            state="unsupported",
            observed_at=observed_at,
            issue="chronyc executable is unavailable",
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return ClockQuality(
            state="failed",
            observed_at=observed_at,
            issue=f"chronyc tracking failed: {error}",
        )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        return ClockQuality(
            state="failed",
            observed_at=observed_at,
            issue=(
                f"chronyc tracking exited with {completed.returncode}: "
                f"{detail or 'no output'}"
            ),
        )
    try:
        return parse_chrony_tracking(completed.stdout, observed_at)
    except ValueError as error:
        return ClockQuality(
            state="failed",
            observed_at=observed_at,
            issue=f"chronyc tracking decode failed: {error}",
        )


def write_text_atomic(path: Path, content: str) -> bool:
    try:
        if path.read_text(encoding="utf-8") == content:
            return False
    except FileNotFoundError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        text=True,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        temporary.replace(path)
        return True
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
