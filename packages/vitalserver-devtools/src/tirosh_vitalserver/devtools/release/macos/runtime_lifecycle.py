from __future__ import annotations

import os
import subprocess
import time
import urllib.error
import urllib.request
from argparse import Namespace
from pathlib import Path

from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
    resolve_path,
)
from tirosh_vitalserver.devtools.release.macos.runtime_app import (
    build_swift,
    sign_runtime_cli_with_entitlements,
    sync_release,
)
from tirosh_vitalserver.devtools.toolchain.workspace_paths import repo_root


def run_macos_runtime_build(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    release_file = resolve_path(root, args.release_file)
    sync_release(root, settings.runtime_dir, release_file)
    build_swift(
        settings.runtime_dir,
        args.sdkroot,
        args.clang_module_cache or str(settings.clang_module_cache),
        settings.helper_product_name,
    )
    return 0


def run_macos_runtime_sync_release(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    release_file = resolve_path(root, args.release_file)
    sync_release(root, settings.runtime_dir, release_file)
    return 0


def run_macos_runtime_sign(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    entitlements = settings.runtime_dir / args.entitlements
    sign_runtime_cli_with_entitlements(
        settings.runtime_cli,
        entitlements,
        args.identity,
    )
    return 0


def run_macos_runtime_require_bridged_identity(args: Namespace) -> int:
    if args.identity != "-":
        return 0
    raise SystemExit(
        "bridged mode requires a real codesign identity with the bridged "
        "networking entitlement.\n"
        "ad-hoc signing can be used for shared/NAT mode only.\n"
        "Set VM_BRIDGED_CODESIGN_IDENTITY, for example:\n"
        "  VM_BRIDGED_CODESIGN_IDENTITY='Developer ID Application: ...' "
        "make vm-up-bridged"
    )


def run_macos_runtime_control(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    vm_home = resolve_path(root, args.vm_home)
    command = [str(settings.runtime_cli), *args.runtime_args]
    env = os.environ.copy()
    env["VITALSERVER_VM_HOME"] = str(vm_home)
    return subprocess.run(command, env=env, check=False).returncode


def run_macos_runtime_start_detached(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    vm_home = resolve_path(root, args.vm_home)
    logs_dir = vm_home / "logs"
    run_dir = vm_home / "data/run"
    legacy_pid = vm_home / "run/vitalserver-vm.pid"
    log_file = logs_dir / "launcher.log"
    logs_dir.mkdir(parents=True, exist_ok=True)
    run_dir.mkdir(parents=True, exist_ok=True)

    if process_is_running(legacy_pid):
        print(f"VM is already running: pid {legacy_pid.read_text().strip()}")
        return 0

    env = os.environ.copy()
    env["VITALSERVER_VM_HOME"] = str(vm_home)
    env["VITALSERVER_VM_DETACHED"] = "1"
    with log_file.open("ab") as log:
        subprocess.Popen(
            [str(settings.runtime_cli), "start"],
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    print(f"VM launcher started in background. Logs: {log_file}")
    return 0


def run_macos_runtime_ip(args: Namespace) -> int:
    ip_file = vm_ip_file(args.vm_home)
    if ip_file.is_file() and ip_file.stat().st_size > 0:
        print(ip_file.read_text().strip())
        return 0
    raise SystemExit(f"VM IP is not available yet: {ip_file}")


def run_macos_runtime_wait_ip(args: Namespace) -> int:
    ip_file = vm_ip_file(args.vm_home)
    print(f"Waiting for VM IP file: {ip_file}")
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        if ip_file.is_file() and ip_file.stat().st_size > 0:
            print(f"VM IP: {ip_file.read_text().strip()}")
            return 0
        time.sleep(2)
    raise SystemExit(f"error: timed out waiting for VM IP. Check {launcher_log(args)}")


def run_macos_runtime_wait_http(args: Namespace) -> int:
    ip = read_vm_ip(args.vm_home)
    url = f"http://{ip}/"
    print(f"Waiting for VM HTTP: {url}")
    deadline = time.monotonic() + args.timeout
    last_status = "not-started"
    while time.monotonic() < deadline:
        ok, status = probe_http(url)
        if ok:
            print(f"VM HTTP ready: {url} -> {status}")
            return 0
        last_status = status
        time.sleep(2)
    raise SystemExit(
        f"error: timed out waiting for VM HTTP: {url} last={last_status}\n"
        f"Check guest bootstrap in {launcher_log(args)}"
    )


def run_macos_runtime_wait_rootfs_ready(args: Namespace) -> int:
    marker = vm_home_path(args.vm_home) / "data/run/rootfs-ready"
    print(f"Waiting for air-gapped rootfs marker: {marker}")
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        if marker.is_file() and marker.stat().st_size > 0:
            print("Air-gapped rootfs marker is ready:")
            for line in marker.read_text().splitlines():
                print(f"  {line}")
            return 0
        time.sleep(3)
    raise SystemExit(
        f"error: timed out waiting for {marker}\n"
        f"Check VM launcher log: {launcher_log(args)}"
    )


def run_macos_runtime_health(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    vm_home = resolve_path(root, args.vm_home)
    ip_file = vm_home / "data/run/vm-ip"
    status = 0

    print("VM health")
    print(f"  home: {vm_home}")
    print("\nVM process:")
    if settings.runtime_cli.is_file() and os.access(settings.runtime_cli, os.X_OK):
        env = os.environ.copy()
        env["VITALSERVER_VM_HOME"] = str(vm_home)
        result = subprocess.run(
            [str(settings.runtime_cli), "status"],
            env=env,
            check=False,
        )
        status |= result.returncode
    else:
        print(f"  missing launcher binary: {settings.runtime_cli}")
        print("  run: make vm-build")
        status = 1

    print("\nVM IP:")
    vm_ip = ""
    if ip_file.is_file() and ip_file.stat().st_size > 0:
        vm_ip = ip_file.read_text().strip()
        print(f"  {vm_ip}")
    else:
        print(f"  missing {ip_file}")
        status = 1

    print("\nGuest HTTP:")
    if vm_ip:
        ok, code = probe_http(f"http://{vm_ip}/")
        if ok:
            print(f"  ok http://{vm_ip}/ -> {code}")
        else:
            print(f"  failed http://{vm_ip}/ -> {code}")
            status = 1
    else:
        print("  skipped because VM IP is unavailable")

    print("\nHost proxy:")
    status |= subprocess.run(
        ["make", "--no-print-directory", "proxy-status"],
        cwd=root,
        check=False,
    ).returncode
    print_listeners(args.proxy_port)
    ok, code = probe_http(f"http://127.0.0.1:{args.proxy_port}/")
    if ok:
        print(f"  ok http://127.0.0.1:{args.proxy_port}/ -> {code}")
    else:
        print(f"  failed http://127.0.0.1:{args.proxy_port}/ -> {code}")
        status = 1
    return status


def process_is_running(pid_file: Path) -> bool:
    if not pid_file.is_file():
        return False
    try:
        pid = int(pid_file.read_text().strip())
        os.kill(pid, 0)
    except (OSError, ValueError):
        return False
    return True


def vm_home_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else repo_root() / path


def vm_ip_file(value: str | Path) -> Path:
    return vm_home_path(value) / "data/run/vm-ip"


def launcher_log(args: Namespace) -> Path:
    return vm_home_path(args.vm_home) / "logs/launcher.log"


def read_vm_ip(vm_home: str | Path) -> str:
    ip_file = vm_ip_file(vm_home)
    if ip_file.is_file() and ip_file.stat().st_size > 0:
        return ip_file.read_text().strip()
    raise SystemExit(f"VM IP is not available yet: {ip_file}")


def probe_http(url: str) -> tuple[bool, str]:
    request = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status = response.status
    except urllib.error.HTTPError as error:
        status = error.code
    except Exception:
        return False, "curl-error"
    return 200 <= status < 400, str(status)


def print_listeners(proxy_port: str) -> None:
    if not shutil_which("lsof"):
        return
    print(f"  listeners on port {proxy_port}:")
    result = subprocess.run(
        ["lsof", "-nP", f"-iTCP:{proxy_port}", "-sTCP:LISTEN"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.stdout:
        for line in result.stdout.splitlines():
            print(f"    {line}")


def shutil_which(name: str) -> str | None:
    from shutil import which

    return which(name)
