#!/usr/bin/env python3
"""Audit host-visible VitalServer runtime permissions on macOS."""

from __future__ import annotations

import argparse
import json
import os
import pwd
import stat
import sys
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PRODUCT_ROOT = Path("/Library/Application Support/TiroshVitalServer")
DEFAULT_HELPER_APP = Path("/Applications/VitalServer Helper.app")
DEFAULT_LAUNCHER = Path("/usr/local/bin/vitalserver-vm")
DEFAULT_UNINSTALLER = Path("/usr/local/bin/tirosh-vitalserver-uninstall")
DEFAULT_PROXY_PLIST = Path("/Library/LaunchDaemons/ai.tirosh.vitalserver.helper.proxy.plist")
DEFAULT_SHARED_ROOT = Path("/Users/Shared/TiroshVitalServer")


@dataclass(frozen=True)
class Probe:
    name: str
    path: Path
    kind: str
    access: tuple[str, ...]
    required: bool


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    product_root = args.product_root
    vm_home = args.vm_home or product_root / "vm"
    probes = list(
        build_probes(
            product_root=product_root,
            vm_home=vm_home,
            require_install=args.require_install,
        )
    )
    results = [audit_probe(probe) for probe in probes]

    if args.json:
        print(json.dumps({"results": results}, indent=2, sort_keys=True))
    else:
        print_human(results)

    return 1 if any(result["status"] == "fail" for result in results) else 0


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-root", type=Path, default=DEFAULT_PRODUCT_ROOT)
    parser.add_argument("--vm-home", type=Path, default=None)
    parser.add_argument(
        "--require-install",
        action="store_true",
        help="Treat missing installed-runtime paths as failures instead of warnings.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print machine-readable audit output.",
    )
    return parser.parse_args(argv)


def build_probes(
    product_root: Path,
    vm_home: Path,
    require_install: bool,
) -> Iterable[Probe]:
    status_dir = product_root / "status"
    logs_dir = product_root / "logs"
    runtime_dir = vm_home / "runtime"
    data_dir = vm_home / "data"
    deploy_dir = data_dir / "deploy"
    run_dir = data_dir / "run"

    installed = require_install or product_root.exists() or DEFAULT_HELPER_APP.exists()
    required = installed

    yield Probe(
        "helperApp",
        DEFAULT_HELPER_APP,
        "directory",
        ("read", "execute"),
        required,
    )
    yield Probe("launcher", DEFAULT_LAUNCHER, "file", ("read", "execute"), required)
    yield Probe(
        "uninstaller",
        DEFAULT_UNINSTALLER,
        "file",
        ("read", "execute"),
        required,
    )
    yield Probe(
        "proxyLaunchDaemon",
        DEFAULT_PROXY_PLIST,
        "file",
        ("read",),
        installed and DEFAULT_PROXY_PLIST.exists(),
    )
    yield Probe("productRoot", product_root, "directory", ("read", "execute"), required)
    yield Probe(
        "statusDirectory",
        status_dir,
        "directory",
        ("read", "execute"),
        required,
    )
    yield Probe(
        "runtimeStatus",
        status_dir / "runtime-status.json",
        "file",
        ("read",),
        installed and status_dir.exists(),
    )
    yield Probe(
        "runtimeEvents",
        status_dir / "runtime-events.jsonl",
        "file",
        ("read",),
        installed and status_dir.exists(),
    )
    yield Probe(
        "runtimeObservabilityDB",
        status_dir / "runtime-observability.sqlite",
        "file",
        ("read",),
        installed and status_dir.exists(),
    )
    yield Probe(
        "logsDirectory",
        logs_dir,
        "directory",
        ("read", "execute"),
        installed and product_root.exists(),
    )
    yield Probe(
        "runtimeHome",
        vm_home,
        "directory",
        ("read", "execute"),
        installed and vm_home.exists(),
    )
    yield Probe(
        "runtimeDirectory",
        runtime_dir,
        "directory",
        ("read", "execute"),
        installed and vm_home.exists(),
    )
    yield Probe(
        "runtimeConfig",
        runtime_dir / "vm-config.json",
        "file",
        ("read",),
        installed and runtime_dir.exists(),
    )
    yield Probe(
        "guestDeployDirectory",
        deploy_dir,
        "directory",
        ("read", "execute"),
        installed and deploy_dir.exists(),
    )
    yield Probe(
        "guestRuntimeConfigSecret",
        deploy_dir / "runtime-config.json",
        "file",
        (),
        installed and deploy_dir.exists(),
    )
    yield Probe(
        "guestRuntimeSettings",
        deploy_dir / "runtime-settings.json",
        "file",
        ("read",),
        installed and deploy_dir.exists(),
    )
    yield Probe(
        "guestRunDirectory",
        run_dir,
        "directory",
        ("read", "execute"),
        installed and run_dir.exists(),
    )
    yield Probe(
        "sharedRoot",
        DEFAULT_SHARED_ROOT,
        "directory",
        ("read", "write", "execute"),
        DEFAULT_SHARED_ROOT.exists(),
    )


def audit_probe(probe: Probe) -> dict[str, object]:
    result: dict[str, object] = {
        "name": probe.name,
        "path": str(probe.path),
        "required": probe.required,
        "expectedKind": probe.kind,
        "expectedAccess": list(probe.access),
    }

    try:
        st = probe.path.stat()
    except FileNotFoundError:
        result["status"] = "fail" if probe.required else "warn"
        result["message"] = "missing"
        return result
    except OSError as exc:
        result["status"] = "fail"
        result["message"] = f"stat failed: {exc}"
        return result

    actual_kind = (
        "directory"
        if stat.S_ISDIR(st.st_mode)
        else "file"
        if stat.S_ISREG(st.st_mode)
        else "other"
    )
    result.update(
        {
            "status": "ok",
            "actualKind": actual_kind,
            "mode": oct(stat.S_IMODE(st.st_mode)),
            "owner": owner_name(st.st_uid),
            "groupId": st.st_gid,
        }
    )

    issues: list[str] = []
    if actual_kind != probe.kind:
        issues.append(f"expected {probe.kind}, found {actual_kind}")

    missing_access = [
        access for access in probe.access if not has_access(probe.path, access)
    ]
    if missing_access:
        issues.append(f"missing access: {', '.join(missing_access)}")

    if issues:
        result["status"] = "fail"
        result["message"] = "; ".join(issues)

    return result


def has_access(path: Path, access: str) -> bool:
    mode = {
        "read": os.R_OK,
        "write": os.W_OK,
        "execute": os.X_OK,
    }[access]
    return os.access(path, mode)


def owner_name(uid: int) -> str:
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


def print_human(results: list[dict[str, object]]) -> None:
    for result in results:
        status = str(result["status"]).upper()
        mode = result.get("mode", "-")
        owner = result.get("owner", "-")
        message = result.get("message", "")
        print(
            (
                f"{status:4} {result['name']}: {result['path']} "
                f"[{mode} {owner}] {message}"
            ).rstrip()
        )


if __name__ == "__main__":
    sys.exit(main())
