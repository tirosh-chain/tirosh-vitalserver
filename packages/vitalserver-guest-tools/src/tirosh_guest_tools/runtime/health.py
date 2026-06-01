from __future__ import annotations

import argparse
import subprocess

from tirosh_guest_tools.common import compose_command, run, systemctl


def main() -> int:
    parser = argparse.ArgumentParser(description="Check guest runtime health.")
    parser.parse_args()

    systemctl("is-active", "--quiet", "docker")
    run(compose_command(["ps"]))
    for url in ["http://127.0.0.1/health", "http://127.0.0.1/ready"]:
        subprocess.run(
            ["curl", "-fsS", "-I", "--max-time", "5", url],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
