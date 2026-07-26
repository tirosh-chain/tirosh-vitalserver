#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ipaddress
import shutil
import subprocess
import tempfile
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the deterministic NoCloud seed for VitalServer Hyper-V."
    )
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--guest-address", default="172.24.0.2")
    parser.add_argument("--host-address", default="172.24.0.1")
    parser.add_argument("--prefix-length", type=int, default=24)
    parser.add_argument("--dns-address", default="1.1.1.1")
    parser.add_argument("--hdiutil", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.run_id.strip():
        raise SystemExit("Hyper-V seed run ID must be non-empty")
    guest = ipaddress.ip_address(args.guest_address)
    host = ipaddress.ip_address(args.host_address)
    network = ipaddress.ip_network(f"{guest}/{args.prefix_length}", strict=False)
    if host not in network or host == guest:
        raise SystemExit(
            "Hyper-V host and guest addresses are incompatible "
            f"host={host} guest={guest} network={network}"
        )
    dns = ipaddress.ip_address(args.dns_address)
    if not args.hdiutil.is_file():
        raise SystemExit(f"hdiutil executable is missing: {args.hdiutil}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".vitalserver-hyperv-seed-", dir=args.output.parent
    ) as temporary:
        seed = Path(temporary) / "seed"
        seed.mkdir()
        (seed / "meta-data").write_text(
            f"instance-id: vitalserver-hyperv-{args.run_id}\n"
            "local-hostname: vitalserver-runtime\n",
            encoding="utf-8",
        )
        (seed / "network-config").write_text(
            "version: 2\n"
            "ethernets:\n"
            "  runtime:\n"
            "    match:\n"
            "      driver: hv_netvsc\n"
            "    set-name: eth0\n"
            f"    addresses: [{guest}/{args.prefix_length}]\n"
            "    routes:\n"
            "      - to: default\n"
            f"        via: {host}\n"
            "    nameservers:\n"
            f"      addresses: [{dns}]\n",
            encoding="utf-8",
        )
        (seed / "user-data").write_text(_user_data(), encoding="utf-8")
        temporary_iso = Path(temporary) / "seed.iso"
        completed = subprocess.run(
            [
                str(args.hdiutil),
                "makehybrid",
                "-iso",
                "-joliet",
                "-default-volume-name",
                "cidata",
                "-o",
                str(temporary_iso),
                str(seed),
            ],
            text=True,
            capture_output=True,
        )
        if completed.returncode != 0:
            raise SystemExit(
                "Hyper-V NoCloud seed build failed "
                f"exitCode={completed.returncode} stderr={completed.stderr.strip()}"
            )
        if not temporary_iso.is_file() or temporary_iso.stat().st_size == 0:
            raise SystemExit("Hyper-V NoCloud seed builder produced no ISO")
        shutil.move(temporary_iso, args.output)
    print(f"Hyper-V NoCloud seed: {args.output}")
    return 0


def _user_data() -> str:
    return (
        "#cloud-config\n"
        "hostname: vitalserver-runtime\n"
        "manage_etc_hosts: true\n"
        "disable_root: true\n"
        "ssh_pwauth: false\n"
        "runcmd:\n"
        "  - [mkdir, -p, /mnt/runtime, /mnt/tirosh, "
        "/mnt/tirosh-vital-files, /mnt/runtime/run, "
        "/mnt/runtime/vital-files, /opt/vitalserver/run]\n"
        "  - [sh, -c, \"grep -Fqx 'LABEL=vital-runtime /mnt/runtime "
        "ext4 defaults,nofail 0 2' /etc/fstab || printf '%s\\n' "
        "'LABEL=vital-runtime /mnt/runtime ext4 defaults,nofail 0 2' "
        ">> /etc/fstab\"]\n"
        "  - [sh, -c, \"grep -Fqx '/opt/vitalserver /mnt/tirosh "
        "none bind 0 0' /etc/fstab || printf '%s\\n' "
        "'/opt/vitalserver /mnt/tirosh none bind 0 0' >> /etc/fstab\"]\n"
        "  - [sh, -c, \"grep -Fqx '/mnt/runtime/run /mnt/tirosh/run "
        "none bind 0 0' /etc/fstab || printf '%s\\n' "
        "'/mnt/runtime/run /mnt/tirosh/run none bind 0 0' >> /etc/fstab\"]\n"
        "  - [sh, -c, \"grep -Fqx '/mnt/runtime/vital-files "
        "/mnt/tirosh-vital-files none bind 0 0' /etc/fstab || "
        "printf '%s\\n' '/mnt/runtime/vital-files "
        "/mnt/tirosh-vital-files none bind 0 0' >> /etc/fstab\"]\n"
        "  - [mount, -a]\n"
        "  - [bash, /opt/vitalserver/hyperv-guest/bootstrap.sh]\n"
        'final_message: "VitalServer Hyper-V cloud-init completed"\n'
    )


if __name__ == "__main__":
    raise SystemExit(main())
