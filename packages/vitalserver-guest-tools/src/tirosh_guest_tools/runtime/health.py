from __future__ import annotations

import subprocess

from tirosh_guest_tools.common import compose_command, run, systemctl


def check_runtime_health() -> None:
    systemctl("is-active", "--quiet", "docker")
    run(compose_command(["ps"]))
    for url in ["http://127.0.0.1/health", "http://127.0.0.1/ready"]:
        subprocess.run(
            ["curl", "-fsS", "-I", "--max-time", "5", url],
            check=True,
            stdout=subprocess.DEVNULL,
        )
