from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

from tirosh_guest_tools.application.bootstrap import (
    BootstrapResultDocument,
    DockerSmokeResult,
    EdgeReadinessProbeResult,
    GuestBootstrapContext,
    GuestBootstrapOperations,
    expected_deploy_bundle_files,
)
from tirosh_guest_tools.application.runtime_data_prepare import prepare_runtime_data
from tirosh_guest_tools.contracts import RuntimeService
from tirosh_guest_tools.infrastructure.common import (
    DEPLOY_DIR,
    RUNTIME_DIR,
    VITAL_FILES_MOUNT_POINT,
    compose_command,
    mount_runtime_share,
    mount_vital_files_share,
    utc_now,
    write_json,
)
from tirosh_guest_tools.infrastructure.system_install import install_guest_tools_runtime

BOOTSTRAP_RESULT = RUNTIME_DIR / "bootstrap-result.json"


def default_bootstrap_context() -> GuestBootstrapContext:
    return GuestBootstrapContext(
        deploy_dir=DEPLOY_DIR,
        runtime_dir=RUNTIME_DIR,
        vital_files_mount=VITAL_FILES_MOUNT_POINT,
        bootstrap_result=BOOTSTRAP_RESULT,
    )


def default_bootstrap_operations() -> GuestBootstrapOperations:
    return GuestBootstrapOperations(
        current_time_seconds=time.time,
        sleep=time.sleep,
        now=utc_now,
        boot_id=read_boot_id,
        mount_shares=mount_shares,
        sync_clock=sync_clock,
        write_bootstrap_result=write_bootstrap_result,
        missing_deploy_bundle_files=missing_deploy_bundle_files,
        expand_root_filesystem=expand_root_filesystem,
        missing_runtime_packages=missing_runtime_packages,
        install_runtime_files=install_runtime_files,
        prepare_runtime_data=prepare_runtime_data,
        write_initial_runtime_state=write_initial_runtime_state,
        start_docker=start_docker,
        start_avahi=start_avahi,
        start_guest_background_services=start_guest_background_services,
        prepare_shared_directories=prepare_shared_directories,
        load_bundled_docker_images=load_bundled_docker_images,
        run_docker_runtime_smoke=run_docker_runtime_smoke,
        cleanup_docker_cache=cleanup_docker_cache,
        build_missing_images=build_missing_images,
        start_compose=start_compose,
        start_container_logs=start_container_logs,
        probe_edge_readiness=probe_edge_readiness,
        write_runtime_state_once=write_initial_runtime_state,
        write_edge_diagnostics=write_edge_diagnostics,
        restart_runtime_state=restart_runtime_state,
        start_optional_testkit=start_optional_testkit,
        runtime_boot_smoke_enabled=runtime_boot_smoke_enabled,
        run_runtime_boot_smoke=run_runtime_boot_smoke,
    )


def mount_shares() -> None:
    mount_runtime_share()
    mount_vital_files_share()


def sync_clock(context: GuestBootstrapContext) -> None:
    host_time_path = context.deploy_dir / "host-time.json"
    try:
        document = json.loads(host_time_path.read_text(encoding="utf-8"))
    except OSError as error:
        raise RuntimeError(
            f"host time contract is unreadable: {host_time_path}: {error}"
        ) from error
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"host time contract is invalid JSON: {host_time_path}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise RuntimeError(f"host time contract must be an object: {host_time_path}")
    schema_version = document.get("schemaVersion")
    epoch_seconds = document.get("epochSeconds")
    updated_at = document.get("updatedAt")
    if schema_version != 1:
        raise RuntimeError(
            f"host time contract schemaVersion is unsupported: {schema_version}"
        )
    if not isinstance(epoch_seconds, int) or epoch_seconds <= 0:
        raise RuntimeError("host time contract epochSeconds must be a positive integer")
    if not isinstance(updated_at, str) or not updated_at:
        raise RuntimeError("host time contract updatedAt must be a non-empty string")
    run(["date", "-u", "-s", f"@{epoch_seconds}"])


def write_bootstrap_result(path: Path, document: BootstrapResultDocument) -> None:
    write_json(
        path,
        {
            "bootID": document.boot_id,
            "message": document.message,
            "operation": document.operation,
            "reasonCodes": list(document.reason_codes),
            "schemaVersion": document.schema_version,
            "status": document.status,
            "updatedAt": document.updated_at,
        },
    )


def missing_deploy_bundle_files(context: GuestBootstrapContext) -> list[Path]:
    return [
        path for path in expected_deploy_bundle_files(context) if not path.is_file()
    ]


def expand_root_filesystem() -> None:
    root_source = command_text(["findmnt", "-n", "-o", "SOURCE", "/"])
    parent_device = optional_command_text(["lsblk", "-no", "PKNAME", root_source])
    partition_number = optional_command_text(["lsblk", "-no", "PARTNUM", root_source])
    filesystem_type = command_text(["findmnt", "-n", "-o", "FSTYPE", "/"])
    if not partition_number:
        partition_number = partition_number_from_source(root_source)
    if not parent_device and partition_number:
        parent_device = parent_device_from_source(root_source, partition_number)
    if not parent_device or not partition_number:
        print(
            "warning: could not resolve root partition for resize: "
            f"{root_source}"
        )
        return
    if shutil.which("growpart") is not None:
        run(["growpart", f"/dev/{parent_device}", partition_number], check=False)
    else:
        print("warning: growpart is not available; root partition may stay small")
    if filesystem_type in {"ext2", "ext3", "ext4"}:
        run(["resize2fs", root_source], check=False)
    elif filesystem_type == "xfs":
        run(["xfs_growfs", "/"], check=False)
    else:
        print(f"warning: unsupported root filesystem for resize: {filesystem_type}")
    run(["df", "-h", "/"])


def missing_runtime_packages() -> list[str]:
    missing: list[str] = []
    for name, command in (
        ("curl", ["curl", "--version"]),
        ("docker", ["docker", "--version"]),
        ("python3-minimal", ["python3", "--version"]),
        ("psmisc", ["fuser", "-V"]),
        ("avahi-daemon", ["avahi-daemon", "--version"]),
        ("growpart", ["growpart", "--help"]),
        ("docker compose", ["docker", "compose", "version"]),
    ):
        if run(command, check=False).returncode != 0:
            missing.append(name)
    with tempfile.TemporaryDirectory(prefix="tirosh-venv-check-") as temporary_dir:
        test_venv = Path(temporary_dir) / "venv"
        venv = run(["python3", "-m", "venv", str(test_venv)], check=False)
    if venv.returncode != 0:
        missing.append("python3-venv/ensurepip")
    return missing


def install_runtime_files(context: GuestBootstrapContext) -> None:
    command_names = (
        "tirosh-runtime-env",
        "tirosh-write-runtime-state",
        "tirosh-runtime-state",
        "tirosh-vitalserver-compose",
        "tirosh-vitalserver-health",
        "tirosh-vitalserver-runtime-boot-smoke",
        "tirosh-vitalserver-runtime-data-prepare",
        "tirosh-vitalserver-container-logs",
        "tirosh-vitalserver-diagnostics",
        "tirosh-vitalserver-redis-backup",
        "tirosh-vitalserver-redis-restore",
        "tirosh-vitalserver-repair-datastore",
        "tirosh-vitalserver-activate-update",
        "tirosh-vitalserver-prepare-update-shutdown",
        "tirosh-vitalserver-command-poller",
    )
    service_files = (
        "tirosh-guest-observability.service",
        "tirosh-runtime-state.service",
        "tirosh-vitalserver-compose.service",
        "tirosh-vitalserver-testkit.service",
        "tirosh-vitalserver-container-logs.service",
        "tirosh-vitalserver-redis-backup.service",
        "tirosh-vitalserver-redis-backup.timer",
        "tirosh-vitalserver-redis-restore.service",
        "tirosh-vitalserver-repair-datastore.service",
        "tirosh-vitalserver-activate-update.service",
        "tirosh-vitalserver-prepare-update-shutdown.service",
        "tirosh-vitalserver-command-poller.service",
    )
    run(["install", "-d", "-m", "0755", "/etc/tirosh"])
    for name in command_names:
        run(
            [
                "install",
                "-m",
                "0755",
                str(context.deploy_dir / "bin" / name),
                f"/usr/local/bin/{name}",
            ]
        )
    install_guest_tools_runtime()
    for name in service_files:
        run(
            [
                "install",
                "-m",
                "0644",
                str(context.deploy_dir / "systemd" / name),
                f"/etc/systemd/system/{name}",
            ]
        )
    systemctl("daemon-reload")
    for service in (
        "tirosh-vitalserver-redis-backup.path",
        "tirosh-vitalserver-redis-restore.path",
        "tirosh-vitalserver-repair-datastore.path",
        "tirosh-vitalserver-activate-update.path",
        "tirosh-vitalserver-prepare-update-shutdown.path",
    ):
        systemctl("disable", "--now", service, check=False)
    for service in (
        RuntimeService.RUNTIME_STATE.value,
        RuntimeService.COMPOSE.value,
        RuntimeService.TESTKIT.value,
        RuntimeService.CONTAINER_LOGS.value,
        RuntimeService.REDIS_BACKUP_TIMER.value,
        RuntimeService.COMMAND_POLLER.value,
        "tirosh-guest-observability.service",
    ):
        systemctl("enable", service)


def write_initial_runtime_state() -> None:
    run(["/usr/local/bin/tirosh-runtime-state", "once"])


def start_docker() -> None:
    systemctl("enable", "--now", "docker")


def start_avahi() -> None:
    run(["hostnamectl", "set-hostname", "tirosh-vitalserver"])
    systemctl("enable", "--now", "avahi-daemon")


def start_guest_background_services() -> None:
    systemctl("start", RuntimeService.REDIS_BACKUP_TIMER.value)
    systemctl("start", RuntimeService.COMMAND_POLLER.value)
    systemctl("start", "tirosh-guest-observability.service")


def prepare_shared_directories(context: GuestBootstrapContext) -> None:
    context.vital_files_mount.mkdir(parents=True, exist_ok=True)
    (context.runtime_dir.parent / "vr-release").mkdir(parents=True, exist_ok=True)


def load_bundled_docker_images(context: GuestBootstrapContext) -> None:
    image_dir = context.deploy_dir / "docker-images"
    if not image_dir.is_dir():
        return
    loaded = False
    bundles = [
        path
        for pattern in ("*.tar", "*.tar.gz", "*.tgz")
        for path in sorted(image_dir.glob(pattern))
    ]
    for image_bundle in bundles:
        print(f"Loading Docker image bundle: {image_bundle}")
        run(["docker", "load", "-i", str(image_bundle)])
        loaded = True
    if loaded:
        print("Bundled Docker images are loaded.")


def run_docker_runtime_smoke(docker_smoke_image: str) -> DockerSmokeResult:
    completed = run(["docker", "image", "inspect", docker_smoke_image], check=False)
    if completed.returncode != 0:
        return DockerSmokeResult(passed=False, missing_image=True)
    smoke = run(
        [
            "docker",
            "run",
            "--rm",
            "--network",
            "none",
            "--security-opt",
            "seccomp=unconfined",
            docker_smoke_image,
            "true",
        ],
        check=False,
    )
    return DockerSmokeResult(passed=smoke.returncode == 0)


def cleanup_docker_cache() -> None:
    run(["docker", "image", "prune", "-f"], check=False)


def build_missing_images() -> None:
    for image, service in (
        ("vitalserver:2.3.4", "app"),
        ("vitalserver-audit-proxy:0.1.0", "audit-proxy"),
    ):
        completed = run(["docker", "image", "inspect", image], check=False)
        if completed.returncode != 0:
            run(compose_command(["build", service]))


def start_compose() -> None:
    systemctl("start", RuntimeService.COMPOSE.value)


def start_container_logs() -> None:
    systemctl("start", RuntimeService.CONTAINER_LOGS.value)


def probe_edge_readiness(
    url: str,
    timeout_seconds: float,
) -> EdgeReadinessProbeResult:
    completed = subprocess.run(
        [
            "curl",
            "-sS",
            "-L",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "--max-time",
            str(timeout_seconds),
            url,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        return EdgeReadinessProbeResult(
            status_code=None,
            failure=command_output(completed),
        )
    try:
        return EdgeReadinessProbeResult(status_code=int(completed.stdout.strip()))
    except ValueError:
        return EdgeReadinessProbeResult(
            status_code=None,
            failure=f"invalid HTTP status output: {completed.stdout.strip()}",
        )


def write_edge_diagnostics() -> None:
    run(compose_command(["ps"]), check=False)
    run(compose_command(["logs", "--tail=200"]), check=False)
    run(["df", "-h", "/"], check=False)


def restart_runtime_state() -> None:
    systemctl("restart", RuntimeService.RUNTIME_STATE.value)


def start_optional_testkit() -> None:
    run(["/usr/local/bin/tirosh-vitalserver-compose", "testkit-up-logged"])


def runtime_boot_smoke_enabled(deploy_dir: Path) -> bool:
    path = deploy_dir / "build-metadata" / "rootfs-input.json"
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise RuntimeError(
            f"runtime boot smoke metadata is unreadable: {path}: {error}"
        ) from error
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"runtime boot smoke metadata is invalid JSON: {path}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise RuntimeError(f"runtime boot smoke metadata must be an object: {path}")
    runtime_boot_smoke = document.get("runtimeBootSmoke")
    if not isinstance(runtime_boot_smoke, dict):
        raise RuntimeError("runtime boot smoke metadata is missing runtimeBootSmoke")
    enabled = runtime_boot_smoke.get("enabled")
    if isinstance(enabled, bool):
        return enabled
    raise RuntimeError("runtime boot smoke enabled flag must be explicit boolean")


def run_runtime_boot_smoke() -> None:
    run(["/usr/local/bin/tirosh-vitalserver-runtime-boot-smoke"])


def read_boot_id() -> str:
    boot_id = Path("/proc/sys/kernel/random/boot_id").read_text(
        encoding="utf-8"
    ).strip()
    if not boot_id:
        raise RuntimeError("guest boot id is empty")
    return boot_id


def parent_device_from_source(root_source: str, partition_number: str) -> str:
    if root_source.startswith("/dev/nvme") or root_source.startswith("/dev/mmcblk"):
        return root_source.removeprefix("/dev/").removesuffix(f"p{partition_number}")
    return root_source.removeprefix("/dev/").removesuffix(partition_number)


def partition_number_from_source(root_source: str) -> str:
    if root_source.startswith("/dev/nvme") or root_source.startswith("/dev/mmcblk"):
        return root_source.rsplit("p", 1)[-1]
    match = re.search(r"(\d+)$", root_source)
    return match.group(1) if match else ""


def systemctl(
    *arguments: str,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return run(["systemctl", *arguments], check=check)


def command_text(arguments: list[str]) -> str:
    output = subprocess.run(
        arguments,
        check=False,
        capture_output=True,
        text=True,
    ).stdout.strip().splitlines()
    if not output:
        raise RuntimeError("command returned no output: " + " ".join(arguments))
    return output[0].strip()


def optional_command_text(arguments: list[str]) -> str:
    output = subprocess.run(
        arguments,
        check=False,
        capture_output=True,
        text=True,
    ).stdout.strip().splitlines()
    return output[0].strip() if output else ""


def run(
    arguments: list[str],
    *,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, check=check, text=True)


def command_output(completed: subprocess.CompletedProcess[str]) -> str:
    output: dict[str, Any] = {
        "returncode": completed.returncode,
        "stderr": completed.stderr.strip() if completed.stderr else "",
        "stdout": completed.stdout.strip() if completed.stdout else "",
    }
    return json.dumps(output, sort_keys=True)
