from __future__ import annotations

import os
import subprocess
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    InstalledHealthInput,
    InstalledStatusInput,
)
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)


def run_installed_status(input: InstalledStatusInput) -> int:
    status = installed_status(input.config)
    return 1 if input.fail_on_unhealthy and status != 0 else 0


def run_installed_health(input: InstalledHealthInput) -> int:
    status = installed_status(input.config)
    health = installed_health(input.config, input.proxy_port)
    return status or health


def installed_status(config: Path) -> int:
    root = repo_root()
    settings = load_macos_release_settings(config, root)
    product_root = Path(settings.install.product_root)
    ip_file = product_root / "vm/data/run/vm-ip"
    status = 0

    print("Installed VM runtime")
    for label, path in [
        ("launcher", Path(settings.install.vm_cli)),
        ("proxy runner", Path(settings.install.proxy_runner)),
        ("uninstaller", Path(settings.install.uninstaller)),
        ("nginx", product_root / "nginx/sbin/nginx"),
    ]:
        if path.is_file() and os.access(path, os.X_OK):
            print(f"  {label}: {path}")
        else:
            print(f"  missing {label}: {path}")
            status = 1

    for label, service in [
        ("launchd vm", "system/com.tirosh.vitalserver-vm"),
        ("launchd proxy", "system/com.tirosh.vitalserver-proxy"),
        ("launchd watchdog", "system/com.tirosh.vitalserver-watchdog"),
    ]:
        if launchd_loaded(service):
            print(f"  {label}: loaded")
        else:
            print(f"  {label}: not loaded")
            status = 1

    if ip_file.is_file() and ip_file.stat().st_size > 0:
        print(f"  vm ip: {ip_file.read_text().strip()}")
    else:
        print(f"  vm ip: waiting for {ip_file}")
        status = 1

    return status


def installed_health(config: Path, proxy_port: str) -> int:
    root = repo_root()
    settings = load_macos_release_settings(config, root)
    product_root = Path(settings.install.product_root)
    ip_file = product_root / "vm/data/run/vm-ip"
    status = 0

    if ip_file.is_file() and ip_file.stat().st_size > 0:
        vm_ip = ip_file.read_text().strip()
        status |= print_http_status("guest http", f"http://{vm_ip}/")
    else:
        status = 1
    status |= print_http_status("host proxy", f"http://127.0.0.1:{proxy_port}/")
    return status


def launchd_loaded(service: str) -> bool:
    return subprocess.run(
        ["launchctl", "print", service],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def print_http_status(label: str, url: str) -> int:
    result = subprocess.run(
        [
            "curl",
            "-sS",
            "-I",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "--max-time",
            "5",
            url,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    code = result.stdout.strip() or "curl-error"
    if result.returncode == 0 and code.isdigit() and 200 <= int(code) < 400:
        print(f"  {label}: ok {url} -> {code}")
        return 0
    print(f"  {label}: failed {url} -> {code}")
    return 1
