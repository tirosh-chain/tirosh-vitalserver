from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Install the released VitalServer testkit wheel.",
    )
    parser.add_argument("--testkit-version", required=True)
    parser.add_argument("--testkit-release-tag", required=True)
    parser.add_argument("--testkit-release-dir", required=True)
    parser.add_argument("--python", default="python3")
    args = parser.parse_args()

    status = require_command("gh") or require_command(args.python)
    if status != 0:
        return status

    release_dir = Path(args.testkit_release_dir)
    release_dir.mkdir(parents=True, exist_ok=True)
    download = subprocess.run(
        [
            "gh",
            "release",
            "download",
            args.testkit_release_tag,
            "--repo",
            "tirosh-chain/tirosh-vitalserver",
            "--pattern",
            "*.whl",
            "--dir",
            str(release_dir),
            "--clobber",
        ],
        check=False,
    )
    if download.returncode != 0:
        return download.returncode

    wheels = sorted(
        release_dir.glob(f"tirosh_vitalserver_testkit-{args.testkit_version}-*.whl")
    )
    if not wheels:
        raise SystemExit(
            "missing downloaded testkit wheel: "
            f"tirosh_vitalserver_testkit-{args.testkit_version}-*.whl"
        )

    wheel = wheels[0]
    print(f"Installing {wheel} with {args.python}")
    return subprocess.run(
        [
            args.python,
            "-m",
            "pip",
            "install",
            "--upgrade",
            str(wheel),
            "pydantic-settings",
        ],
        check=False,
    ).returncode


def require_command(tool: str) -> int:
    if shutil.which(tool):
        return 0
    print(f"missing: {tool}")
    return 127


if __name__ == "__main__":
    raise SystemExit(main())
