from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.macos_release.installed_runtime import (
    run_installed_health,
    run_installed_status,
)
from tirosh_vitalserver.devtools.application.inputs import (
    InstalledHealthInput,
    InstalledStatusInput,
)


def inspect_installed_runtime(input: InstalledStatusInput) -> int:
    return run_installed_status(input)


def check_installed_runtime_health(input: InstalledHealthInput) -> int:
    return run_installed_health(input)
