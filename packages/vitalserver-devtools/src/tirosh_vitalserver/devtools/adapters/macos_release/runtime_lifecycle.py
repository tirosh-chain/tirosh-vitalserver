from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.guest_image.runtime_data_disk import (
    prepare_ephemeral_runtime_data_disk,
)
from tirosh_vitalserver.devtools.adapters.macos_release.runtime_app import (
    build_swift,
    sign_runtime_cli_with_entitlements,
    sync_release,
)
from tirosh_vitalserver.devtools.adapters.macos_release.runtime_paths import (
    vm_home_path,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    GoldenRootfsPreflightInput,
    RequireBridgedIdentityInput,
    RootfsRunInput,
    RuntimeBootSmokeRunInput,
    RuntimeBuildInput,
    RuntimeControlInput,
    RuntimeGuestAddressOwnerInput,
    RuntimeHealthInput,
    RuntimeSignInput,
    RuntimeSyncReleaseInput,
    RuntimeVmHomeInput,
    RuntimeWaitInput,
)
from tirosh_vitalserver.devtools.config.build_toml import load_build_toml
from tirosh_vitalserver.devtools.config.guest_image import load_guest_runtime_config
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.core.guest_image import runtime_data_disk_plan
from tirosh_vitalserver.devtools.core.preflight import (
    PreflightCheck,
    PreflightReport,
    PreflightStatus,
    print_preflight_report,
)

APT_SNAPSHOT_PROBE_ATTEMPTS = 2
APT_SNAPSHOT_PROBE_RETRY_DELAY_SECONDS = 2
APT_SNAPSHOT_PROBE_TIMEOUT_SECONDS = 30

ROOTFS_REQUIRED_STAGES = (
    "runtime-data-mount",
    "runtime-data-configure",
    "docker-service",
    "runtime-version",
    "docker-image-load",
    "docker-smoke",
    "disk-space",
    "compose-build",
    "compose-up",
    "edge-ready",
)

ROOTFS_TERMINAL_LOG_PATTERNS = (
    "Internal error: Oops:",
    "Internal error: Oops - Undefined instruction",
    "Undefined instruction",
    "seccomp_run_filters",
    "Kernel panic - not syncing",
    "rcu: INFO: rcu_preempt detected stalls",
    "Unable to handle kernel NULL pointer dereference",
    "EXT4-fs error",
    "Aborting journal",
    "Journal has aborted",
    "checksum invalid",
    "Remounting filesystem read-only",
    "Read-only file system",
    "invalid ELF header",
    "Input/output error",
    "Segmentation fault",
    "terminated by signal ILL",
    "Caught <ILL>",
    "Illegal instruction",
    "Freezing execution",
    "BUG: Bad rss-counter state",
    "Attempted to kill init",
)

RUNTIME_BOOT_SMOKE_REQUIRED_STAGES = (
    "bootstrap-result",
    "runtime-observation",
    "systemd-units",
    "runtime-data",
    "http",
    "compose-services",
    "guest-control-api",
    "disk-health",
    "capabilities",
    "command-dispatch",
    "feature-readiness",
)


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
    if input.runtime_args[:1] == ["start"]:
        write_runtime_start_contracts(vm_home)
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

    write_runtime_start_contracts(vm_home)
    env = os.environ.copy()
    env["VITALSERVER_VM_HOME"] = str(vm_home)
    env["VITALSERVER_VM_DETACHED"] = "1"
    with log_file.open("wb") as log:
        subprocess.Popen(
            [str(settings.runtime_cli), "start"],
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    print(f"VM launcher started in background. Logs: {log_file}")
    return 0


def write_runtime_start_contracts(vm_home: Path) -> None:
    write_host_time_contract(vm_home)
    write_default_redis_relay_contract(vm_home)


def write_host_time_contract(vm_home: Path) -> None:
    epoch_seconds = int(time.time())
    host_time = {
        "epochSeconds": epoch_seconds,
        "schemaVersion": 1,
        "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch_seconds)),
    }
    path = vm_home / "data/deploy/host-time.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(host_time, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"host time contract written: {path} epochSeconds={epoch_seconds}")


def write_default_redis_relay_contract(vm_home: Path) -> None:
    deploy_dir = vm_home / "data/deploy"
    run_dir = vm_home / "data/run"
    config_dir = deploy_dir / "redis-relay-config"
    secrets_dir = deploy_dir / "redis-relay-secrets"
    status_dir = run_dir / "redis-relay-status"
    config_path = config_dir / "redis-relay.toml"

    config_dir.mkdir(parents=True, exist_ok=True)
    secrets_dir.mkdir(parents=True, exist_ok=True)
    status_dir.mkdir(parents=True, exist_ok=True)
    if config_path.exists():
        print(f"redis relay contract already exists: {config_path}")
        return

    config_path.write_text(default_redis_relay_toml(), encoding="utf-8")
    print(f"redis relay disabled contract written: {config_path}")


def default_redis_relay_toml() -> str:
    return "\n".join(
        [
            "[redis_relay]",
            "enabled = false",
            'scope = "vital_reconstruction"',
            "include_recorder_network_context = false",
            "interval_seconds = 1.0",
            "scan_count = 1000",
            "",
            "[source]",
            'host = "redis"',
            "port = 6379",
            "database = 0",
            "",
            "[target]",
            'url = "redis://redis.example:6379/0"',
            "",
        ]
    )


def require_no_running_runtime(input: RuntimeVmHomeInput) -> int:
    root = repo_root()
    vm_home = resolve_path(root, input.vm_home)
    running_processes = running_vm_processes_for_home(vm_home)
    if running_processes:
        raise SystemExit(
            "error: VM launcher process is still running for VM_HOME; "
            f"refusing to continue with mutable runtime files: {vm_home}: "
            f"pids={','.join(str(pid) for pid in running_processes)}"
        )
    print(f"No VM launcher process is running for {vm_home}")
    return 0


def force_stop_runtime(input: RuntimeWaitInput) -> int:
    root = repo_root()
    vm_home = resolve_path(root, input.vm_home)
    deadline = time.monotonic() + input.timeout

    terminate_processes_for_home(vm_home, signal=15, label="SIGTERM")
    while time.monotonic() < deadline:
        if not running_vm_processes_for_home(vm_home):
            print(f"VM launcher process stopped for {vm_home}")
            return 0
        time.sleep(1)

    remaining = running_vm_processes_for_home(vm_home)
    if not remaining:
        print(f"VM launcher process stopped for {vm_home}")
        return 0

    print(
        "VM launcher process ignored graceful stop; sending SIGKILL for "
        f"{vm_home}: pids={','.join(str(pid) for pid in remaining)}"
    )
    terminate_processes_for_home(vm_home, signal=9, label="SIGKILL")

    kill_deadline = time.monotonic() + max(1, min(input.timeout, 5))
    while time.monotonic() < kill_deadline:
        if not running_vm_processes_for_home(vm_home):
            print(f"VM launcher process force stopped for {vm_home}")
            return 0
        time.sleep(1)

    remaining = running_vm_processes_for_home(vm_home)
    raise SystemExit(
        "error: VM launcher process is still running after force stop for "
        f"{vm_home}: pids={','.join(str(pid) for pid in remaining)}"
    )


def begin_golden_rootfs_run(input: RootfsRunInput) -> int:
    root = repo_root()
    config_path = resolve_path(root, input.config)
    vm_home = resolve_path(root, input.vm_home)
    run_dir = vm_home / "run"
    data_run_dir = vm_home / "data/run"
    run_dir.mkdir(parents=True, exist_ok=True)
    data_run_dir.mkdir(parents=True, exist_ok=True)
    require_vm_config(vm_home)

    stale_paths = [
        data_run_dir / "rootfs-ready",
        data_run_dir / "rootfs-runtime-manifest.json",
        data_run_dir / "rootfs-smoke-diagnostics",
        data_run_dir / "rootfs-failure.json",
        data_run_dir / "rootfs-apt-plan.json",
        data_run_dir / "rootfs-apt-plan.txt",
        data_run_dir / "rootfs-apt-installed.json",
        data_run_dir / "rootfs-apt-installed.txt",
    ]
    removed: list[str] = []
    for path in stale_paths:
        if path.is_dir():
            shutil.rmtree(path)
            removed.append(str(path))
        elif path.exists():
            path.unlink()
            removed.append(str(path))

    runtime_config = load_guest_runtime_config(load_build_toml(config_path))
    runtime_data = prepare_ephemeral_runtime_data_disk(
        runtime_data_disk_plan(
            config_path=config_path,
            vm_home=vm_home,
            runtime_config=runtime_config,
        )
    )
    write_vm_config_runtime_data_disk_path(vm_home, str(runtime_data["path"]))

    context = {
        "schemaVersion": 1,
        "runId": input.run_id,
        "createdAt": utc_timestamp(),
        "removedStaleProof": removed,
        "runtimeDataDisk": runtime_data,
    }
    context_path = rootfs_run_context_path(vm_home)
    context_path.write_text(
        json.dumps(context, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Golden rootfs run started: runId={input.run_id}")
    if removed:
        print("Invalidated stale rootfs proof:")
        for removed_path in removed:
            print(f"  {removed_path}")
    return 0


def prepare_runtime_data_disk(input: RuntimeVmHomeInput) -> int:
    root = repo_root()
    config_path = resolve_path(root, input.config)
    vm_home = resolve_path(root, input.vm_home)
    require_vm_config(vm_home)
    runtime_config = load_guest_runtime_config(load_build_toml(config_path))
    runtime_data = prepare_ephemeral_runtime_data_disk(
        runtime_data_disk_plan(
            config_path=config_path,
            vm_home=vm_home,
            runtime_config=runtime_config,
        )
    )
    write_vm_config_runtime_data_disk_path(vm_home, str(runtime_data["path"]))
    print(f"Runtime data disk is ready: {runtime_data['path']}")
    return 0


def preflight_golden_rootfs(input: GoldenRootfsPreflightInput) -> int:
    root = repo_root()
    vm_home = resolve_path(root, input.vm_home)
    report = golden_rootfs_preflight_report(
        vm_home=vm_home,
        expected_run_id=input.expected_run_id,
    )
    print_preflight_report(report)
    if report.passed:
        return 0
    raise SystemExit(1)


def golden_rootfs_preflight_report(
    *,
    vm_home: Path,
    expected_run_id: str,
) -> PreflightReport:
    checks: list[PreflightCheck] = []
    rootfs_input = vm_home / "data/deploy/build-metadata/rootfs-input.json"
    run_context = rootfs_run_context_path(vm_home)
    checks.append(check_expected_run_id(expected_run_id))
    checks.append(check_no_vm_process(vm_home))
    checks.append(check_json_run_id(run_context, expected_run_id, "golden-run-context"))
    metadata_check, metadata = check_rootfs_input_metadata(
        rootfs_input,
        expected_run_id,
    )
    checks.append(metadata_check)
    checks.extend(check_rootfs_preflight_proof_absence(vm_home))
    snapshot = read_metadata_apt_snapshot(metadata)
    if snapshot:
        checks.extend(check_apt_snapshot_available(snapshot))
    return PreflightReport(
        name="golden-rootfs",
        checks=tuple(checks),
    )


def check_expected_run_id(expected_run_id: str) -> PreflightCheck:
    if not expected_run_id.strip():
        return PreflightCheck(
            name="expected-run-id",
            status=PreflightStatus.MISSING,
            message="expected golden rootfs runId is missing",
        )
    return PreflightCheck(
        name="expected-run-id",
        status=PreflightStatus.PASSED,
        message=f"expected runId={expected_run_id}",
    )


def check_no_vm_process(vm_home: Path) -> PreflightCheck:
    try:
        pids = running_vm_processes_for_home(vm_home)
    except SystemExit as error:
        return PreflightCheck(
            name="vm-process",
            status=PreflightStatus.FAILED,
            message="failed to inspect VM process state",
            detail=str(error),
        )
    if pids:
        return PreflightCheck(
            name="vm-process",
            status=PreflightStatus.BLOCKED,
            message="VM launcher process is already running",
            detail=f"vmHome={vm_home} pids={','.join(str(pid) for pid in pids)}",
        )
    return PreflightCheck(
        name="vm-process",
        status=PreflightStatus.PASSED,
        message=f"no VM launcher process is running for {vm_home}",
    )


def check_json_run_id(path: Path, expected_run_id: str, name: str) -> PreflightCheck:
    document_check, document = read_json_object_for_preflight(path, name)
    if document_check.blocks:
        return document_check
    run_id = document.get("runId")
    if not isinstance(run_id, str) or not run_id.strip():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message=f"{name} is missing runId",
            detail=str(path),
        )
    if run_id != expected_run_id:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.BLOCKED,
            message=f"{name} runId does not match expected run",
            detail=f"expected={expected_run_id} actual={run_id} path={path}",
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.PASSED,
        message=f"{name} runId matches expected run",
        detail=f"runId={run_id}",
    )


def check_rootfs_input_metadata(
    path: Path,
    expected_run_id: str,
) -> tuple[PreflightCheck, dict[str, object]]:
    document_check, document = read_json_object_for_preflight(
        path,
        "rootfs-input-metadata",
    )
    if document_check.blocks:
        return document_check, {}
    schema_version = document.get("schemaVersion")
    if schema_version != 1:
        return (
            PreflightCheck(
                name="rootfs-input-metadata",
                status=PreflightStatus.INVALID,
                message="rootfs input metadata schema is unsupported",
                detail=f"expected=1 actual={schema_version} path={path}",
            ),
            document,
        )
    run_id = document.get("runId")
    if run_id != expected_run_id:
        return (
            PreflightCheck(
                name="rootfs-input-metadata",
                status=PreflightStatus.BLOCKED,
                message="rootfs input metadata runId does not match expected run",
                detail=f"expected={expected_run_id} actual={run_id} path={path}",
            ),
            document,
        )
    guest_clock = document.get("guestClockUtc")
    if not isinstance(guest_clock, str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",
        guest_clock,
    ):
        return (
            PreflightCheck(
                name="rootfs-input-metadata",
                status=PreflightStatus.INVALID,
                message="rootfs input metadata has invalid guestClockUtc",
                detail=f"path={path}",
            ),
            document,
        )
    ubuntu = document.get("ubuntu")
    if not isinstance(ubuntu, dict):
        return (
            PreflightCheck(
                name="rootfs-input-metadata",
                status=PreflightStatus.MISSING,
                message="rootfs input metadata is missing ubuntu object",
                detail=f"path={path}",
            ),
            document,
        )
    snapshot = ubuntu.get("aptSnapshot")
    if not isinstance(snapshot, str) or not re.fullmatch(
        r"\d{8}T\d{6}Z",
        snapshot,
    ):
        return (
            PreflightCheck(
                name="rootfs-input-metadata",
                status=PreflightStatus.INVALID,
                message="rootfs input metadata has invalid ubuntu.aptSnapshot",
                detail=f"snapshot={snapshot!r} path={path}",
            ),
            document,
        )
    return (
        PreflightCheck(
            name="rootfs-input-metadata",
            status=PreflightStatus.PASSED,
            message="rootfs input metadata is valid",
            detail=f"runId={expected_run_id} aptSnapshot={snapshot}",
        ),
        document,
    )


def read_json_object_for_preflight(
    path: Path,
    name: str,
) -> tuple[PreflightCheck, dict[str, object]]:
    if not path.exists():
        return (
            PreflightCheck(
                name=name,
                status=PreflightStatus.MISSING,
                message=f"{name} is missing",
                detail=str(path),
            ),
            {},
        )
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except PermissionError as error:
        return (
            PreflightCheck(
                name=name,
                status=PreflightStatus.FAILED,
                message=f"{name} read was denied",
                detail=f"{path}: {error}",
            ),
            {},
        )
    except (OSError, json.JSONDecodeError) as error:
        return (
            PreflightCheck(
                name=name,
                status=PreflightStatus.INVALID,
                message=f"{name} is unreadable",
                detail=f"{path}: {error}",
            ),
            {},
        )
    if not isinstance(document, dict):
        return (
            PreflightCheck(
                name=name,
                status=PreflightStatus.INVALID,
                message=f"{name} is not an object",
                detail=str(path),
            ),
            {},
        )
    return (
        PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=f"{name} is readable",
            detail=str(path),
        ),
        document,
    )


def check_rootfs_preflight_proof_absence(vm_home: Path) -> list[PreflightCheck]:
    run_dir = vm_home / "data/run"
    paths = {
        "rootfs-ready": run_dir / "rootfs-ready",
        "rootfs-runtime-manifest": run_dir / "rootfs-runtime-manifest.json",
        "rootfs-failure": run_dir / "rootfs-failure.json",
        "rootfs-apt-plan": run_dir / "rootfs-apt-plan.json",
    }
    checks: list[PreflightCheck] = []
    for name, path in paths.items():
        if path.exists():
            checks.append(
                PreflightCheck(
                    name=name,
                    status=PreflightStatus.BLOCKED,
                    message=f"{name} exists before VM start",
                    detail=str(path),
                )
            )
        else:
            checks.append(
                PreflightCheck(
                    name=name,
                    status=PreflightStatus.PASSED,
                    message=f"{name} is absent before VM start",
                    detail=str(path),
                )
            )
    return checks


def read_metadata_apt_snapshot(metadata: dict[str, object]) -> str | None:
    ubuntu = metadata.get("ubuntu")
    if not isinstance(ubuntu, dict):
        return None
    snapshot = ubuntu.get("aptSnapshot")
    return snapshot if isinstance(snapshot, str) else None


def check_apt_snapshot_available(snapshot: str) -> list[PreflightCheck]:
    urls = [
        f"https://snapshot.ubuntu.com/ubuntu/{snapshot}/dists/noble/InRelease",
        f"https://snapshot.ubuntu.com/ubuntu/{snapshot}/dists/noble-updates/InRelease",
        f"https://snapshot.ubuntu.com/ubuntu/{snapshot}/dists/noble-security/InRelease",
    ]
    return [probe_apt_snapshot_url(url) for url in urls]


def probe_apt_snapshot_url(
    url: str,
    *,
    attempts: int = APT_SNAPSHOT_PROBE_ATTEMPTS,
    timeout_seconds: int = APT_SNAPSHOT_PROBE_TIMEOUT_SECONDS,
    retry_delay_seconds: int = APT_SNAPSHOT_PROBE_RETRY_DELAY_SECONDS,
) -> PreflightCheck:
    failures: list[str] = []
    bounded_attempts = max(1, attempts)
    for attempt in range(1, bounded_attempts + 1):
        check = probe_apt_snapshot_url_once(url, timeout_seconds=timeout_seconds)
        if not check.blocks:
            return check
        failures.append(f"attempt={attempt} {check.message}; {check.detail}")
        if attempt < bounded_attempts:
            time.sleep(max(0, retry_delay_seconds))

    return PreflightCheck(
        name="apt-snapshot",
        status=PreflightStatus.UNAVAILABLE,
        message="Ubuntu apt snapshot endpoint is unavailable after retries",
        detail="\n".join(failures),
    )


def probe_apt_snapshot_url_once(
    url: str,
    *,
    timeout_seconds: int,
) -> PreflightCheck:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "vitalserver-devtools"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            status = response.getcode()
            response.read(1)
    except urllib.error.HTTPError as error:
        return PreflightCheck(
            name="apt-snapshot",
            status=PreflightStatus.UNAVAILABLE,
            message="Ubuntu apt snapshot endpoint is unavailable",
            detail=f"url={url} status={error.code}",
        )
    except urllib.error.URLError as error:
        return PreflightCheck(
            name="apt-snapshot",
            status=PreflightStatus.UNAVAILABLE,
            message="Ubuntu apt snapshot endpoint could not be reached",
            detail=f"url={url} reason={error.reason}",
        )
    except TimeoutError as error:
        return PreflightCheck(
            name="apt-snapshot",
            status=PreflightStatus.UNAVAILABLE,
            message="Ubuntu apt snapshot endpoint timed out",
            detail=f"url={url} error={error}",
        )
    if status < 200 or status >= 300:
        return PreflightCheck(
            name="apt-snapshot",
            status=PreflightStatus.UNAVAILABLE,
            message="Ubuntu apt snapshot endpoint returned unexpected status",
            detail=f"url={url} status={status}",
        )
    return PreflightCheck(
        name="apt-snapshot",
        status=PreflightStatus.PASSED,
        message="Ubuntu apt snapshot endpoint is reachable",
        detail=f"url={url} status={status}",
    )


def write_vm_config_runtime_data_disk_path(
    vm_home: Path,
    runtime_data_disk_path: str,
) -> None:
    config_path = vm_home / "runtime/vm-config.json"
    require_vm_config(vm_home)
    try:
        document = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"error: VM config is unreadable: {config_path}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise SystemExit(f"error: VM config is invalid: expected object: {config_path}")
    document["runtimeDataDiskPath"] = runtime_data_disk_path
    config_path.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def require_vm_config(vm_home: Path) -> None:
    config_path = vm_home / "runtime/vm-config.json"
    if not config_path.is_file():
        raise SystemExit(
            "error: VM config is missing; initialize the VM before starting "
            f"golden rootfs run: {config_path}"
        )


def begin_runtime_boot_smoke_run(input: RuntimeBootSmokeRunInput) -> int:
    root = repo_root()
    vm_home = resolve_path(root, input.vm_home)
    run_dir = vm_home / "run"
    data_run_dir = vm_home / "data/run"
    run_dir.mkdir(parents=True, exist_ok=True)
    data_run_dir.mkdir(parents=True, exist_ok=True)

    stale_paths = [
        data_run_dir / "runtime-boot-smoke-manifest.json",
        data_run_dir / "bootstrap-result.json",
        run_dir / "vm-lifecycle.json",
    ]
    removed: list[str] = []
    for path in stale_paths:
        if path.is_dir():
            shutil.rmtree(path)
            removed.append(str(path))
        elif path.exists():
            path.unlink()
            removed.append(str(path))

    context = {
        "schemaVersion": 1,
        "runId": input.run_id,
        "createdAt": utc_timestamp(),
        "removedStaleProof": removed,
    }
    context_path = runtime_boot_smoke_run_context_path(vm_home)
    context_path.write_text(
        json.dumps(context, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Runtime boot smoke run started: runId={input.run_id}")
    if removed:
        print("Invalidated stale runtime boot smoke proof:")
        for removed_path in removed:
            print(f"  {removed_path}")
    return 0


class RuntimeBootstrapAddressReadError(Exception):
    pass


def runtime_vm_ip_file(vm_home: str | Path) -> Path:
    return vm_home_path(vm_home) / "data/run/vm-ip"


def read_runtime_bootstrap_vm_ip(vm_home: str | Path) -> str:
    address_file = runtime_vm_ip_file(vm_home)
    if not address_file.exists():
        raise RuntimeBootstrapAddressReadError(
            f"missing VM IP bootstrap file: {address_file}"
        )
    if not address_file.is_file():
        raise RuntimeBootstrapAddressReadError(
            f"invalid VM IP bootstrap path: not a file: {address_file}"
        )
    try:
        value = address_file.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeBootstrapAddressReadError(
            f"failed to read VM IP bootstrap file: {address_file}: {error}"
        ) from error
    value = value.strip()
    if not value:
        raise RuntimeBootstrapAddressReadError(
            f"invalid VM IP bootstrap file: empty address: {address_file}"
        )
    return value


def print_runtime_guest_address_proxy_upstream(
    input: RuntimeGuestAddressOwnerInput,
) -> int:
    bootstrap_address = read_runtime_bootstrap_vm_ip(input.vm_home)
    runtime_control_guest_address_request(
        input,
        method="PUT",
        path="/platform/runtime-endpoint",
        body={"address": bootstrap_address},
    )
    state = runtime_control_guest_address_request(
        input,
        method="GET",
        path="/platform/runtime-endpoint",
        body=None,
    )
    address = loaded_guest_address_from_owner_state(state)
    print(f"{address}:80")
    return 0


def runtime_control_guest_address_request(
    input: RuntimeGuestAddressOwnerInput,
    *,
    method: str,
    path: str,
    body: dict[str, str] | None,
) -> dict[str, object]:
    base_url = input.runtime_control_api_base_url.rstrip("/")
    request_body = None
    headers = {
        "Accept": "application/json",
        input.runtime_control_api_token_header: input.runtime_control_api_token,
    }
    if body is not None:
        request_body = json.dumps(body, separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{base_url}{path}",
        data=request_body,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(
            request,
            timeout=input.runtime_control_api_timeout,
        ) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise SystemExit(
            "error: Runtime Control Guest address owner request failed: "
            f"method={method} path={path} status={error.code} detail={detail}"
        ) from error
    except urllib.error.URLError as error:
        raise SystemExit(
            "error: Runtime Control Guest address owner is unavailable: "
            f"method={method} path={path} reason={error.reason}"
        ) from error
    except TimeoutError as error:
        raise SystemExit(
            "error: Runtime Control Guest address owner request timed out: "
            f"method={method} path={path}"
        ) from error
    try:
        decoded = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(
            "error: Runtime Control Guest address owner returned invalid JSON: "
            f"method={method} path={path} error={error}"
        ) from error
    if not isinstance(decoded, dict):
        raise SystemExit(
            "error: Runtime Control Guest address owner returned invalid payload: "
            f"method={method} path={path}"
        )
    return decoded


def loaded_guest_address_from_owner_state(state: dict[str, object]) -> str:
    resource_state = state.get("state")
    read = state.get("read")
    if resource_state != "loaded" or not isinstance(read, dict):
        raise SystemExit(
            "error: Runtime Control Guest address owner is not loaded: "
            f"state={resource_state!r} readError={state.get('readError')!r}"
        )
    read_state = read.get("state")
    address = read.get("address")
    if read_state != "loaded" or not isinstance(address, str) or not address.strip():
        raise SystemExit(
            "error: Runtime Control Guest address owner returned invalid loaded "
            f"read: state={read_state!r} address={address!r}"
        )
    return address.strip()


def probe_guest_runtime_http(vm_ip: str) -> tuple[bool, str]:
    root_url = f"http://{vm_ip}:80/"
    recorder_url = f"http://{vm_ip}:80/recorder-ingress/health"
    root_ready, root_status = probe_http_request(root_url, method="HEAD")
    if not root_ready:
        return False, f"root={root_status}"
    recorder_ready, recorder_status = probe_http_request(recorder_url, method="GET")
    if not recorder_ready:
        return False, f"root={root_status} recorder-ingress={recorder_status}"
    return True, f"root={root_status} recorder-ingress={recorder_status}"


def probe_http_request(url: str, *, method: str) -> tuple[bool, str]:
    request = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status = response.status
    except urllib.error.HTTPError as error:
        status = error.code
    except urllib.error.URLError as error:
        return False, f"unreachable:{error.reason}"
    except TimeoutError:
        return False, "timeout"
    except OSError as error:
        return False, f"failed:{error}"
    return 200 <= status < 400, str(status)


def print_runtime_ip(input: RuntimeVmHomeInput) -> int:
    try:
        print(read_runtime_bootstrap_vm_ip(input.vm_home))
    except RuntimeBootstrapAddressReadError as error:
        raise SystemExit(str(error)) from error
    return 0


def wait_for_runtime_ip(input: RuntimeWaitInput) -> int:
    address_file = runtime_vm_ip_file(input.vm_home)
    print(f"Waiting for VM IP bootstrap file: {address_file}")
    deadline = time.monotonic() + input.timeout
    last_error = "not-started"
    while time.monotonic() < deadline:
        try:
            vm_ip = read_runtime_bootstrap_vm_ip(input.vm_home)
            print(f"VM IP: {vm_ip}")
            return 0
        except RuntimeBootstrapAddressReadError as error:
            last_error = str(error)
        time.sleep(2)
    raise SystemExit(
        f"error: timed out waiting for VM IP bootstrap file: {address_file} "
        f"last={last_error}\nCheck {launcher_log(input.vm_home)}"
    )


def wait_for_runtime_http(input: RuntimeWaitInput) -> int:
    address_file = runtime_vm_ip_file(input.vm_home)
    print(f"Waiting for VM HTTP through bootstrap address: {address_file}")
    deadline = time.monotonic() + input.timeout
    last_status = "not-started"
    while time.monotonic() < deadline:
        try:
            vm_ip = read_runtime_bootstrap_vm_ip(input.vm_home)
            ready, status = probe_guest_runtime_http(vm_ip)
            if ready:
                print(f"VM HTTP ready: upstream=http://{vm_ip}:80 status={status}")
                return 0
            last_status = status
        except RuntimeBootstrapAddressReadError as error:
            last_status = str(error)
        time.sleep(2)
    raise SystemExit(
        "error: timed out waiting for VM HTTP through bootstrap address: "
        f"{address_file} "
        f"last={last_status}\n"
        f"Check guest bootstrap in {launcher_log(input.vm_home)}"
    )


def wait_for_rootfs_ready(input: RuntimeWaitInput) -> int:
    marker = vm_home_path(input.vm_home) / "data/run/rootfs-ready"
    manifest = vm_home_path(input.vm_home) / "data/run/rootfs-runtime-manifest.json"
    failure = vm_home_path(input.vm_home) / "data/run/rootfs-failure.json"
    apt_plan = vm_home_path(input.vm_home) / "data/run/rootfs-apt-plan.json"
    expected_run_id = expected_rootfs_run_id(input.vm_home, input.expected_run_id)
    print(f"Waiting for air-gapped rootfs marker: {marker}")
    if expected_run_id:
        print(f"Expected golden rootfs runId: {expected_run_id}")
    deadline = time.monotonic() + input.timeout
    last_state = "not-started"
    while time.monotonic() < deadline:
        failure_result = inspect_rootfs_failure_marker(
            failure,
            expected_run_id=expected_run_id,
        )
        if failure_result["terminal"]:
            raise SystemExit(str(failure_result["message"]))
        if failure_result["message"]:
            last_state = str(failure_result["message"])
        apt_plan_result = inspect_rootfs_apt_plan(
            apt_plan,
            expected_run_id=expected_run_id,
        )
        if apt_plan_result["terminal"]:
            raise SystemExit(str(apt_plan_result["message"]))
        if apt_plan_result["message"]:
            last_state = str(apt_plan_result["message"])
        manifest_result = inspect_rootfs_manifest(
            manifest,
            expected_run_id=expected_run_id,
        )
        if manifest_result["terminal"]:
            raise SystemExit(str(manifest_result["message"]))
        last_state = str(manifest_result["message"])
        if marker.is_file() and marker.stat().st_size > 0:
            marker_result = inspect_rootfs_ready_marker(
                marker,
                expected_run_id=expected_run_id,
            )
            if marker_result["terminal"]:
                raise SystemExit(str(marker_result["message"]))
            if marker_result["ready"] and manifest_result["ready"]:
                print("Air-gapped rootfs marker is ready:")
                print(f"  runId={marker_result['runId']}")
                print(f"  manifest={manifest}")
                print("  manifestStatus=passed")
                return 0
            last_state = (
                f"{marker_result['message']}; {manifest_result['message']}"
            )
        fail_if_runtime_lifecycle_failed(input.vm_home)
        fail_if_rootfs_launcher_log_has_terminal_failure(
            input.vm_home,
            expected_run_id=expected_run_id,
        )
        time.sleep(3)
    raise SystemExit(
        f"error: timed out waiting for {marker}: last={last_state}\n"
        f"Check VM launcher log: {launcher_log(input.vm_home)}"
    )


def wait_for_runtime_boot_smoke(input: RuntimeWaitInput) -> int:
    data_run_dir = vm_home_path(input.vm_home) / "data/run"
    manifest = data_run_dir / "runtime-boot-smoke-manifest.json"
    bootstrap_result = data_run_dir / "bootstrap-result.json"
    expected_run_id = input.expected_run_id
    print(f"Waiting for runtime boot smoke manifest: {manifest}")
    if expected_run_id:
        print(f"Expected runtime boot smoke runId: {expected_run_id}")
    deadline = time.monotonic() + input.timeout
    last_state = "not-started"
    while time.monotonic() < deadline:
        bootstrap_state = inspect_runtime_bootstrap_result(
            bootstrap_result,
            expected_run_id=expected_run_id,
        )
        if bootstrap_state["terminal"]:
            raise SystemExit(
                f"{bootstrap_state['message']}\n"
                f"Check VM launcher log: {launcher_log(input.vm_home)}"
            )
        if bootstrap_state["message"]:
            last_state = str(bootstrap_state["message"])
        result = inspect_runtime_boot_smoke_manifest(
            manifest,
            expected_run_id=expected_run_id,
        )
        if result["terminal"]:
            raise SystemExit(
                f"{result['message']}\n"
                f"Check VM launcher log: {launcher_log(input.vm_home)}"
            )
        if result["ready"]:
            print("SUCCESS: runtime boot smoke passed")
            print(f"  runId={result['runId']}")
            print(f"  manifest={manifest}")
            return 0
        last_state = str(result["message"])
        fail_if_runtime_lifecycle_failed(input.vm_home)
        fail_if_runtime_lifecycle_stopped(input.vm_home, "runtime boot smoke")
        time.sleep(3)
    raise SystemExit(
        f"error: timed out waiting for runtime boot smoke: {manifest}: "
        f"last={last_state}\nCheck VM launcher log: {launcher_log(input.vm_home)}"
    )


def wait_for_runtime_stopped(input: RuntimeWaitInput) -> int:
    vm_home = vm_home_path(input.vm_home)
    lifecycle = vm_home / "run/vm-lifecycle.json"
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
            if state == "failed":
                terminal_reason = document.get("terminalReason", "unknown")
                message = document.get("message", "")
                raise SystemExit(
                    "error: VM lifecycle failed while waiting for stopped: "
                    f"terminalReason={terminal_reason} message={message}\n"
                    f"Check VM launcher log: {launcher_log(input.vm_home)}"
                )
            last_state = str(state)
        except (OSError, json.JSONDecodeError) as error:
            last_state = str(error)
        if not running_vm_processes_for_home(vm_home):
            print("VM launcher process is not running")
            return 0
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
        vm_ip = read_runtime_bootstrap_vm_ip(vm_home)
        print(f"  {vm_ip}")
    except RuntimeBootstrapAddressReadError as error:
        print(f"  unavailable: {error}")
        status = 1

    print("\nGuest HTTP:")
    if vm_ip:
        ok, code = probe_guest_runtime_http(vm_ip)
        if ok:
            print(f"  ok http://{vm_ip}:80 -> {code}")
        else:
            print(f"  failed http://{vm_ip}:80 -> {code}")
            status = 1
    else:
        print("  skipped because VM IP bootstrap address is unavailable")

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


def terminate_processes_for_home(vm_home: Path, *, signal: int, label: str) -> None:
    pids = running_vm_processes_for_home(vm_home)
    if not pids:
        print(f"No VM launcher process is running for {vm_home}")
        return
    for pid in pids:
        try:
            os.kill(pid, signal)
            print(f"sent {label} to VM launcher pid={pid} vmHome={vm_home}")
        except ProcessLookupError:
            print(f"VM launcher already stopped before {label}: pid={pid}")
        except PermissionError as error:
            raise SystemExit(
                f"error: failed to send {label} to VM launcher pid={pid}: {error}"
            ) from error


def fail_if_runtime_lifecycle_failed(vm_home: str | Path) -> None:
    lifecycle = vm_home_path(vm_home) / "run/vm-lifecycle.json"
    if not lifecycle.exists():
        return
    try:
        document = json.loads(lifecycle.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"error: failed to read VM lifecycle while waiting for rootfs: "
            f"{lifecycle}: {error}"
        ) from error

    state = document.get("state")
    if state != "failed":
        return
    terminal_reason = document.get("terminalReason", "unknown")
    message = document.get("message", "")
    raise SystemExit(
        "error: VM lifecycle failed while waiting for rootfs marker: "
        f"terminalReason={terminal_reason} message={message}\n"
        f"Check VM launcher log: {launcher_log(vm_home)}"
    )


def fail_if_runtime_lifecycle_stopped(vm_home: str | Path, operation: str) -> None:
    lifecycle = vm_home_path(vm_home) / "run/vm-lifecycle.json"
    if not lifecycle.exists():
        return
    try:
        document = json.loads(lifecycle.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"error: failed to read VM lifecycle while waiting for {operation}: "
            f"{lifecycle}: {error}"
        ) from error

    state = document.get("state")
    if state == "stopped":
        raise SystemExit(
            f"error: VM lifecycle stopped while waiting for {operation}\n"
            f"Check VM launcher log: {launcher_log(vm_home)}"
        )


def fail_if_rootfs_launcher_log_has_terminal_failure(
    vm_home: str | Path,
    *,
    expected_run_id: str | None = None,
) -> None:
    log_file = launcher_log(vm_home)
    if not log_file.exists():
        return
    try:
        log_text = log_file.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        raise SystemExit(
            "error: failed to read VM launcher log while waiting for rootfs: "
            f"{log_file}: {error}"
        ) from error

    for pattern in ROOTFS_TERMINAL_LOG_PATTERNS:
        if pattern not in log_text:
            continue
        matched_line = first_log_line_containing(log_text, pattern)
        raise SystemExit(
            "error: VM launcher log shows terminal guest failure while waiting "
            f"for rootfs marker: runId={expected_run_id or 'unknown'} "
            f"pattern={pattern!r}"
            f"{f' line={matched_line!r}' if matched_line else ''}\n"
            f"Check VM launcher log: {log_file}"
        )


def first_log_line_containing(log_text: str, pattern: str) -> str | None:
    for line in log_text.splitlines():
        if pattern in line:
            return line.strip()
    return None


def inspect_rootfs_manifest(
    manifest: Path,
    *,
    expected_run_id: str | None,
) -> dict[str, object]:
    if not manifest.is_file():
        return {
            "ready": False,
            "terminal": False,
            "message": f"manifest missing: {manifest}",
        }
    try:
        document = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs manifest is unreadable: {manifest}: {error}",
        }
    if not isinstance(document, dict):
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs manifest is not an object: {manifest}",
        }
    run_id = document.get("runId")
    if not isinstance(run_id, str) or not run_id.strip():
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs manifest is missing runId: {manifest}",
        }
    if expected_run_id and run_id != expected_run_id:
        return {
            "ready": False,
            "terminal": False,
            "message": (
                "stale rootfs manifest runId mismatch: "
                f"expected={expected_run_id} actual={run_id}"
            ),
        }
    schema_version = document.get("schemaVersion")
    if schema_version != 2:
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: rootfs manifest schema is unsupported while waiting: "
                f"expected=2 actual={schema_version} manifest={manifest}"
            ),
        }
    stages = document.get("stages")
    if not isinstance(stages, list):
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs manifest is missing stages: {manifest}",
        }
    for stage_name in ROOTFS_REQUIRED_STAGES:
        stage = rootfs_stage(stages, stage_name)
        if stage is None:
            return {
                "ready": False,
                "terminal": False,
                "message": f"waiting for rootfs stage: {stage_name}",
            }
        status = stage.get("status")
        if status == "passed":
            continue
        if status in {"failed", "timeout"}:
            return {
                "ready": False,
                "terminal": True,
                "message": (
                    f"error: rootfs stage failed while waiting: "
                    f"name={stage_name} status={status} "
                    f"message={stage.get('message')}"
                ),
            }
        return {
            "ready": False,
            "terminal": False,
            "message": f"waiting for rootfs stage: {stage_name} status={status}",
        }
    cleanup = document.get("cleanup")
    cleanup_status = cleanup.get("status") if isinstance(cleanup, dict) else None
    if cleanup_status == "passed":
        return {
            "ready": True,
            "terminal": False,
            "message": "manifest passed",
        }
    if cleanup_status == "cleanup-failed":
        return {
            "ready": False,
            "terminal": True,
            "message": "error: rootfs cleanup failed while waiting",
        }
    return {
        "ready": False,
        "terminal": False,
        "message": f"waiting for rootfs cleanup: status={cleanup_status}",
    }


def inspect_rootfs_ready_marker(
    marker: Path,
    *,
    expected_run_id: str | None,
) -> dict[str, object]:
    try:
        document = json.loads(marker.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs ready marker is unreadable: {marker}: {error}",
        }
    if not isinstance(document, dict):
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs ready marker is not an object: {marker}",
        }
    run_id = document.get("runId")
    if expected_run_id and run_id != expected_run_id:
        return {
            "ready": False,
            "terminal": False,
            "runId": run_id,
            "message": (
                "stale rootfs ready marker runId mismatch: "
                f"expected={expected_run_id} actual={run_id}"
            ),
        }
    if not isinstance(run_id, str) or not run_id.strip():
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs ready marker is missing runId: {marker}",
        }
    if not rootfs_guest_tools_dependency_proof_is_valid(
        document.get("pythonDependencies")
    ):
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: rootfs ready marker is missing or has invalid Guest Tools "
                f"dependency proof: {marker}"
            ),
        }
    return {
        "ready": True,
        "terminal": False,
        "runId": run_id,
        "message": "ready marker passed",
    }


def rootfs_guest_tools_dependency_proof_is_valid(value: object) -> bool:
    if not isinstance(value, dict):
        return False
    dependencies = value.get("dependencies")
    return (
        value.get("status") == "passed"
        and isinstance(value.get("proof"), str)
        and bool(value["proof"].strip())
        and isinstance(value.get("target"), str)
        and bool(value["target"].strip())
        and isinstance(dependencies, dict)
        and isinstance(dependencies.get("alembic"), str)
        and bool(dependencies["alembic"].strip())
        and isinstance(dependencies.get("sqlalchemy"), str)
        and bool(dependencies["sqlalchemy"].strip())
    )


def inspect_rootfs_failure_marker(
    failure: Path,
    *,
    expected_run_id: str | None,
) -> dict[str, object]:
    if not failure.is_file():
        return {
            "ready": False,
            "terminal": False,
            "message": "",
        }
    try:
        document = json.loads(failure.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ready": False,
            "terminal": True,
            "message": (
                f"error: rootfs failure marker is unreadable: "
                f"{failure}: {error}"
            ),
        }
    if not isinstance(document, dict):
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs failure marker is not an object: {failure}",
        }
    run_id = document.get("runId")
    if expected_run_id and run_id and run_id != expected_run_id:
        return {
            "ready": False,
            "terminal": False,
            "message": (
                "stale rootfs failure marker runId mismatch: "
                f"expected={expected_run_id} actual={run_id}"
            ),
        }
    stage = document.get("stage", "unknown")
    exit_code = document.get("exitCode", "unknown")
    reason = document.get("reason", "unknown")
    apt_plan_path = document.get("aptPlanPath", "")
    return {
        "ready": False,
        "terminal": True,
        "message": (
            "error: guest rootfs preparation failed while waiting for "
            f"rootfs marker: runId={run_id or 'unknown'} stage={stage} "
            f"exitCode={exit_code} reason={reason} "
            f"failure={failure} aptPlan={apt_plan_path}"
        ),
    }


def inspect_rootfs_apt_plan(
    apt_plan: Path,
    *,
    expected_run_id: str | None,
) -> dict[str, object]:
    if not apt_plan.is_file():
        return {
            "ready": False,
            "terminal": False,
            "message": "",
        }
    try:
        document = json.loads(apt_plan.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs apt plan is unreadable: {apt_plan}: {error}",
        }
    if not isinstance(document, dict):
        return {
            "ready": False,
            "terminal": True,
            "message": f"error: rootfs apt plan is not an object: {apt_plan}",
        }
    run_id = document.get("runId")
    if expected_run_id and run_id != expected_run_id:
        return {
            "ready": False,
            "terminal": False,
            "message": (
                "stale rootfs apt plan runId mismatch: "
                f"expected={expected_run_id} actual={run_id}"
            ),
        }
    status = document.get("status")
    if status == "blocked":
        blocked = document.get("blockedUpgrades")
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: rootfs apt plan mutates base runtime packages while "
                f"waiting for rootfs marker: blockedUpgrades={blocked} "
                f"aptPlan={apt_plan}"
            ),
        }
    if status == "allowed":
        return {
            "ready": False,
            "terminal": False,
            "message": "rootfs apt plan allowed",
        }
    return {
        "ready": False,
        "terminal": True,
        "message": (
            f"error: rootfs apt plan has unsupported status: "
            f"status={status} aptPlan={apt_plan}"
        ),
    }


def inspect_runtime_boot_smoke_manifest(
    manifest: Path,
    *,
    expected_run_id: str | None,
) -> dict[str, object]:
    if not manifest.is_file():
        return {
            "ready": False,
            "terminal": False,
            "message": f"runtime boot smoke manifest missing: {manifest}",
        }
    try:
        document = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ready": False,
            "terminal": True,
            "message": (
                f"error: runtime boot smoke manifest is unreadable: "
                f"{manifest}: {error}"
            ),
        }
    if not isinstance(document, dict):
        return {
            "ready": False,
            "terminal": True,
            "message": (
                f"error: runtime boot smoke manifest is not an object: {manifest}"
            ),
        }
    run_id = document.get("runId")
    if not isinstance(run_id, str) or not run_id.strip():
        return {
            "ready": False,
            "terminal": True,
            "message": (
                f"error: runtime boot smoke manifest is missing runId: {manifest}"
            ),
        }
    if expected_run_id and run_id != expected_run_id:
        return {
            "ready": False,
            "terminal": False,
            "message": (
                "stale runtime boot smoke manifest runId mismatch: "
                f"expected={expected_run_id} actual={run_id}"
            ),
        }
    schema_version = document.get("schemaVersion")
    if schema_version != 1:
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: runtime boot smoke manifest schema is unsupported: "
                f"expected=1 actual={schema_version} manifest={manifest}"
            ),
        }
    status = document.get("status")
    stages = document.get("stages")
    if not isinstance(stages, list):
        return {
            "ready": False,
            "terminal": True,
            "message": (
                f"error: runtime boot smoke manifest is missing stages: {manifest}"
            ),
        }
    for stage in stages:
        if not isinstance(stage, dict):
            return {
                "ready": False,
                "terminal": True,
                "message": (
                    "error: runtime boot smoke manifest stage is invalid: "
                    f"{manifest}"
                ),
            }
        stage_status = stage.get("status")
        if stage_status in {"failed", "timeout", "cleanup-failed"}:
            return {
                "ready": False,
                "terminal": True,
                "message": (
                    "error: runtime boot smoke stage failed while waiting: "
                    f"name={stage.get('name')} status={stage_status} "
                    f"runId={run_id} manifest={manifest} "
                    f"message={stage.get('message')}"
                ),
            }
    if status == "passed":
        return {
            "ready": True,
            "terminal": False,
            "runId": run_id,
            "message": "runtime boot smoke passed",
        }
    for stage_name in RUNTIME_BOOT_SMOKE_REQUIRED_STAGES:
        stage = rootfs_stage(stages, stage_name)
        if stage is None:
            return {
                "ready": False,
                "terminal": False,
                "message": f"waiting for runtime boot smoke stage: {stage_name}",
            }
        stage_status = stage.get("status")
        if stage_status == "passed":
            continue
        if stage_status in {"failed", "timeout", "cleanup-failed"}:
            return {
                "ready": False,
                "terminal": True,
                "message": (
                    "error: runtime boot smoke stage failed while waiting: "
                    f"name={stage_name} status={stage_status} "
                    f"runId={run_id} manifest={manifest} "
                    f"message={stage.get('message')}"
                ),
            }
        return {
            "ready": False,
            "terminal": False,
            "message": (
                f"waiting for runtime boot smoke stage: "
                f"{stage_name} status={stage_status}"
            ),
        }
    if status == "failed":
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: runtime boot smoke failed: "
                f"runId={run_id} manifest={manifest}"
            ),
        }
    return {
        "ready": False,
        "terminal": False,
        "message": f"waiting for runtime boot smoke status: {status}",
    }


def inspect_runtime_bootstrap_result(
    bootstrap_result: Path,
    *,
    expected_run_id: str | None,
) -> dict[str, object]:
    if not bootstrap_result.is_file():
        return {
            "ready": False,
            "terminal": False,
            "message": "",
        }
    try:
        document = json.loads(bootstrap_result.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: runtime boot smoke bootstrap result is unreadable: "
                f"{bootstrap_result}: {error}"
            ),
        }
    if not isinstance(document, dict):
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: runtime boot smoke bootstrap result is not an object: "
                f"{bootstrap_result}"
            ),
        }
    status = document.get("status")
    if not isinstance(status, str) or not status.strip():
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: runtime boot smoke bootstrap result is missing status: "
                f"{bootstrap_result}"
            ),
        }
    if status == "failed":
        reason_codes = document.get("reasonCodes")
        if (
            not isinstance(reason_codes, list)
            or not all(isinstance(code, str) and code for code in reason_codes)
        ):
            return {
                "ready": False,
                "terminal": True,
                "message": (
                    "error: runtime boot smoke bootstrap result has invalid "
                    f"reasonCodes: runId={expected_run_id or 'unknown'} "
                    f"bootstrapResult={bootstrap_result}"
                ),
            }
        message = document.get("message")
        if not isinstance(message, str) or not message.strip():
            return {
                "ready": False,
                "terminal": True,
                "message": (
                    "error: runtime boot smoke bootstrap result has missing "
                    f"failure message: runId={expected_run_id or 'unknown'} "
                    f"bootstrapResult={bootstrap_result}"
                ),
            }
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: runtime boot smoke bootstrap failed: "
                f"runId={expected_run_id or 'unknown'} "
                "stage=bootstrap-result "
                f"reasonCodes={reason_codes} message={message} "
                f"bootstrapResult={bootstrap_result}"
            ),
        }
    if status not in {"running", "completed"}:
        return {
            "ready": False,
            "terminal": True,
            "message": (
                "error: runtime boot smoke bootstrap result has unsupported "
                f"status: runId={expected_run_id or 'unknown'} status={status} "
                f"bootstrapResult={bootstrap_result}"
            ),
        }
    return {
        "ready": False,
        "terminal": False,
        "message": f"runtime boot smoke bootstrap is {status}",
    }


def rootfs_stage(stages: list[object], name: str) -> dict[str, object] | None:
    for stage in stages:
        if isinstance(stage, dict) and stage.get("name") == name:
            return stage
    return None


def expected_rootfs_run_id(
    vm_home: str | Path,
    explicit: str | None,
) -> str | None:
    if explicit:
        return explicit
    context = rootfs_run_context_path(vm_home_path(vm_home))
    if not context.is_file():
        return None
    try:
        document = json.loads(context.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"error: failed to read golden rootfs run context: {context}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise SystemExit(
            f"error: golden rootfs run context is invalid: expected object: {context}"
        )
    run_id = document.get("runId")
    if not isinstance(run_id, str) or not run_id.strip():
        raise SystemExit(
            f"error: golden rootfs run context is missing runId: {context}"
        )
    return run_id


def rootfs_run_context_path(vm_home: Path) -> Path:
    return vm_home / "run/golden-rootfs-run.json"


def runtime_boot_smoke_run_context_path(vm_home: Path) -> Path:
    return vm_home / "run/runtime-boot-smoke-run.json"


def utc_timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


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
