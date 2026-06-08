from __future__ import annotations

import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_app import (
    build_swift,
    sign_runtime_cli_with_entitlements,
    sync_release,
)
from tirosh_vitalserver.devtools.adapters.macos_release.runtime_state import (
    RuntimeStateReadError,
    read_runtime_state,
    read_runtime_state_guest_http,
    read_runtime_state_string,
    read_runtime_state_vm_ip,
    runtime_state_file,
    vm_home_path,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    RequireBridgedIdentityInput,
    RuntimeBuildInput,
    RuntimeControlInput,
    RuntimeHealthInput,
    RuntimeSignInput,
    RuntimeSyncReleaseInput,
    RuntimeVmHomeInput,
    RuntimeWaitInput,
)
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path


def build_runtime(input: RuntimeBuildInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    sync_release(root, settings.runtime_dir, release_file)
    build_swift(
        settings.runtime_dir,
        input.sdkroot,
        input.clang_module_cache or str(settings.clang_module_cache),
        settings.helper_product_name,
    )
    return 0


def sync_runtime_release_sources(input: RuntimeSyncReleaseInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    sync_release(root, settings.runtime_dir, release_file)
    return 0


def sign_runtime(input: RuntimeSignInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    entitlements = settings.runtime_dir / input.entitlements
    sign_runtime_cli_with_entitlements(
        settings.runtime_cli,
        entitlements,
        input.identity,
    )
    return 0


def require_bridged_codesign_identity(input: RequireBridgedIdentityInput) -> int:
    if input.identity != "-":
        return 0
    raise SystemExit(
        "bridged mode requires a real codesign identity with the bridged "
        "networking entitlement.\n"
        "ad-hoc signing can be used for shared/NAT mode only.\n"
        "Set VM_BRIDGED_CODESIGN_IDENTITY, for example:\n"
        "  VM_BRIDGED_CODESIGN_IDENTITY='Developer ID Application: ...' "
        "make vm-up-bridged"
    )


def control_runtime(input: RuntimeControlInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    vm_home = resolve_path(root, input.vm_home)
    command = [str(settings.runtime_cli), *input.runtime_args]
    env = os.environ.copy()
    env["VITALSERVER_VM_HOME"] = str(vm_home)
    return subprocess.run(command, env=env, check=False).returncode


def start_runtime_detached(input: RuntimeVmHomeInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    vm_home = resolve_path(root, input.vm_home)
    logs_dir = vm_home / "logs"
    run_dir = vm_home / "data/run"
    legacy_pid = vm_home / "run/vitalserver-vm.pid"
    log_file = logs_dir / "launcher.log"
    logs_dir.mkdir(parents=True, exist_ok=True)
    run_dir.mkdir(parents=True, exist_ok=True)

    running_processes = running_vm_processes_for_home(vm_home)
    if len(running_processes) > 1:
        raise SystemExit(
            "error: multiple VM launcher processes already use this VM_HOME; "
            f"refusing to start another VM for {vm_home}: "
            f"pids={','.join(str(pid) for pid in running_processes)}"
        )
    if len(running_processes) == 1:
        print(f"VM is already running for {vm_home}: pid {running_processes[0]}")
        return 0

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


def print_runtime_ip(input: RuntimeVmHomeInput) -> int:
    try:
        print(read_runtime_state_vm_ip(input.vm_home))
    except RuntimeStateReadError as error:
        raise SystemExit(str(error)) from error
    return 0


def wait_for_runtime_ip(input: RuntimeWaitInput) -> int:
    state_file = runtime_state_file(input.vm_home)
    print(f"Waiting for runtime-state VM IP: {state_file}")
    deadline = time.monotonic() + input.timeout
    last_error = "not-started"
    while time.monotonic() < deadline:
        try:
            vm_ip = read_runtime_state_vm_ip(input.vm_home)
            print(f"VM IP: {vm_ip}")
            return 0
        except RuntimeStateReadError as error:
            last_error = str(error)
        time.sleep(2)
    raise SystemExit(
        f"error: timed out waiting for VM IP in runtime state: {state_file} "
        f"last={last_error}\nCheck {launcher_log(input.vm_home)}"
    )


def wait_for_runtime_http(input: RuntimeWaitInput) -> int:
    state_file = runtime_state_file(input.vm_home)
    print(f"Waiting for runtime-state guestHTTP: {state_file}")
    deadline = time.monotonic() + input.timeout
    last_status = "not-started"
    while time.monotonic() < deadline:
        try:
            status = read_runtime_state_guest_http(input.vm_home)
            if successful_http_status(status):
                print(f"VM HTTP ready: guestHTTP={status}")
                return 0
            last_status = status
        except RuntimeStateReadError as error:
            last_status = str(error)
        time.sleep(2)
    raise SystemExit(
        f"error: timed out waiting for VM HTTP in runtime state: {state_file} "
        f"last={last_status}\n"
        f"Check guest bootstrap in {launcher_log(input.vm_home)}"
    )


def wait_for_rootfs_ready(input: RuntimeWaitInput) -> int:
    marker = vm_home_path(input.vm_home) / "data/run/rootfs-ready"
    print(f"Waiting for air-gapped rootfs marker: {marker}")
    deadline = time.monotonic() + input.timeout
    while time.monotonic() < deadline:
        if marker.is_file() and marker.stat().st_size > 0:
            print("Air-gapped rootfs marker is ready:")
            for line in marker.read_text().splitlines():
                print(f"  {line}")
            return 0
        time.sleep(3)
    raise SystemExit(
        f"error: timed out waiting for {marker}\n"
        f"Check VM launcher log: {launcher_log(input.vm_home)}"
    )


def wait_for_runtime_stopped(input: RuntimeWaitInput) -> int:
    lifecycle = vm_home_path(input.vm_home) / "run/vm-lifecycle.json"
    print(f"Waiting for VM lifecycle stopped: {lifecycle}")
    deadline = time.monotonic() + input.timeout
    last_state = "not-started"
    while time.monotonic() < deadline:
        try:
            document = json.loads(lifecycle.read_text(encoding="utf-8"))
            state = document.get("state")
            if state == "stopped":
                print("VM lifecycle is stopped")
                return 0
            last_state = str(state)
        except (OSError, json.JSONDecodeError) as error:
            last_state = str(error)
        time.sleep(2)
    raise SystemExit(
        f"error: timed out waiting for VM lifecycle stopped: {lifecycle} "
        f"last={last_state}\nCheck VM launcher log: {launcher_log(input.vm_home)}"
    )


def check_runtime_health(input: RuntimeHealthInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    vm_home = resolve_path(root, input.vm_home)
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
    try:
        runtime_state = read_runtime_state(vm_home)
        vm_ip = read_runtime_state_string(runtime_state, "vmIP", vm_home)
        guest_http = read_runtime_state_string(runtime_state, "guestHTTP", vm_home)
        print(f"  {vm_ip}")
    except RuntimeStateReadError as error:
        guest_http = ""
        print(f"  unavailable: {error}")
        status = 1

    print("\nGuest HTTP:")
    if guest_http:
        if successful_http_status(guest_http):
            print(f"  ok reported guestHTTP={guest_http}")
        else:
            print(f"  failed reported guestHTTP={guest_http}")
            status = 1
    else:
        print("  skipped because runtime state guestHTTP is unavailable")

    print("\nHost proxy:")
    status |= subprocess.run(
        ["make", "--no-print-directory", "proxy-status"],
        cwd=root,
        check=False,
    ).returncode
    print_listeners(input.proxy_port)
    ok, code = probe_http(f"http://127.0.0.1:{input.proxy_port}/")
    if ok:
        print(f"  ok http://127.0.0.1:{input.proxy_port}/ -> {code}")
    else:
        print(f"  failed http://127.0.0.1:{input.proxy_port}/ -> {code}")
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


def running_vm_processes_for_home(vm_home: Path) -> list[int]:
    result = subprocess.run(
        ["ps", "eww", "-axo", "pid=,command="],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            "error: failed to inspect running VM processes before start: "
            f"{result.stderr.strip() or result.returncode}"
        )

    vm_home_token = f"VITALSERVER_VM_HOME={vm_home}"
    pids: list[int] = []
    for line in result.stdout.splitlines():
        text = line.strip()
        if "vitalserver-vm start" not in text or vm_home_token not in text:
            continue
        pid_text = text.split(maxsplit=1)[0]
        try:
            pids.append(int(pid_text))
        except ValueError:
            raise SystemExit(
                "error: failed to parse VM process pid before start: "
                f"line={line}"
            ) from None
    return pids


def launcher_log(vm_home: str | Path) -> Path:
    return vm_home_path(vm_home) / "logs/launcher.log"


def successful_http_status(status: str) -> bool:
    return status.isdigit() and 200 <= int(status) < 400


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
