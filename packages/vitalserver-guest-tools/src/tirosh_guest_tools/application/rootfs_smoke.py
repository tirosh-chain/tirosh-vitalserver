from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from tirosh_guest_tools.application.runtime_data_contract import (
    RuntimeDataContract,
    prepare_runtime_data_directories,
)
from tirosh_guest_tools.contracts import RootfsSmokeStatus
from tirosh_guest_tools.infrastructure.common import (
    DEPLOY_DIR,
    RUNTIME_DIR,
    VITAL_FILES_MOUNT_POINT,
    mount_runtime_share,
    mount_vital_files_share,
    prepare_container_bind_source_directories,
    utc_now,
    write_json,
)

DOCKER_SMOKE_TIMEOUT_SECONDS = 60.0
DOCKER_IMAGE_LOAD_TIMEOUT_SECONDS = 240.0
DOCKER_SECCOMP_SECURITY_OPT = "seccomp=unconfined"
COMPOSE_BUILD_TIMEOUT_SECONDS = 600.0
COMPOSE_UP_TIMEOUT_SECONDS = 300.0
EDGE_READY_TIMEOUT_SECONDS = 600.0
EDGE_READY_POLL_SECONDS = 3.0
EDGE_READY_HTTP_TIMEOUT_SECONDS = 5.0
COMPOSE_CLEANUP_TIMEOUT_SECONDS = 180.0
DOCKER_PRUNE_TIMEOUT_SECONDS = 300.0
DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS = 30.0
MINIMUM_DISK_FREE_KIB = 1024 * 1024
MINIMUM_DISK_FREE_INODES = 1024


@dataclass(frozen=True)
class RootfsSmokeContext:
    runtime_dir: Path
    deploy_dir: Path
    vital_files_mount: Path
    manifest_path: Path
    apt_plan_path: Path
    apt_installed_path: Path
    docker_image_bundle_path: Path
    diagnostics_dir: Path
    compose_project_name: str
    docker_smoke_image: str
    local_docker_smoke_image: str
    run_id: str
    test_mode: bool
    fail_stage: str
    fail_cleanup: bool
    minimum_disk_free_kib: int
    runtime_data: RuntimeDataContract | None
    docker_daemon_config_path: Path
    containerd_config_path: Path
    rootfs_docker_store_path: Path
    rootfs_containerd_store_path: Path


@dataclass(frozen=True)
class RootfsSmokeOperations:
    mount_runtime_share: Callable[[], None]
    mount_vital_files_share: Callable[[], None]
    run: Callable[..., subprocess.CompletedProcess[str]]
    http_status: Callable[[str, float], int]
    sleep: Callable[[float], None]


@dataclass(frozen=True)
class SmokeStageResult:
    name: str
    status: RootfsSmokeStatus
    started_at: str
    completed_at: str
    message: str
    details: dict[str, Any] = field(default_factory=dict)

    def as_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status.value,
            "startedAt": self.started_at,
            "completedAt": self.completed_at,
            "message": self.message,
            "details": self.details,
        }


class RootfsSmokeStageFailed(RuntimeError):
    pass


class RootfsSmokeCommandFailed(RuntimeError):
    def __init__(self, completed: subprocess.CompletedProcess[str]) -> None:
        self.completed = completed
        command = (
            " ".join(completed.args)
            if isinstance(completed.args, list)
            else str(completed.args)
        )
        super().__init__(
            f"command failed: {command} exit={completed.returncode} "
            f"stdout={completed.stdout} stderr={completed.stderr}"
        )


@dataclass
class RootfsSmokeRun:
    context: RootfsSmokeContext
    operations: RootfsSmokeOperations
    created_at: str = field(default_factory=utc_now)
    stages: list[SmokeStageResult] = field(default_factory=list)
    runtime_versions: dict[str, str] = field(
        default_factory=lambda: {
            "kernel": "",
            "docker": "",
            "containerd": "",
            "runc": "",
            "compose": "",
        }
    )
    cleanup: dict[str, Any] = field(
        default_factory=lambda: {
            "status": RootfsSmokeStatus.NOT_RUN.value,
            "message": "cleanup has not run yet",
        }
    )
    runtime_data: dict[str, Any] = field(
        default_factory=lambda: {
            "status": RootfsSmokeStatus.NOT_RUN.value,
            "message": "runtime data disk mount has not run yet",
        }
    )
    docker_images: dict[str, Any] = field(
        default_factory=lambda: {
            "status": RootfsSmokeStatus.NOT_RUN.value,
            "message": "Docker image bundle validation has not run yet",
        }
    )

    def write_manifest(self) -> None:
        write_json(self.context.manifest_path, self.as_json())

    def as_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": 2,
            "runId": self.context.run_id,
            "createdAt": self.created_at,
            "updatedAt": utc_now(),
            "ubuntu": {
                **read_ubuntu_metadata(self.context.deploy_dir),
                "kernel": self.runtime_versions["kernel"],
            },
            "runtime": {
                "docker": self.runtime_versions["docker"],
                "containerd": self.runtime_versions["containerd"],
                "runc": self.runtime_versions["runc"],
                "compose": self.runtime_versions["compose"],
            },
            "apt": read_apt_plan(self.context.apt_plan_path),
            "aptInstalled": read_apt_installed(self.context.apt_installed_path),
            "runtimeData": self.runtime_data,
            "dockerImages": self.docker_images,
            "stages": [stage.as_json() for stage in self.stages],
            "cleanup": self.cleanup,
            "diagnostics": {"path": str(self.context.diagnostics_dir)},
        }


def default_context() -> RootfsSmokeContext:
    metadata = read_rootfs_input_document(DEPLOY_DIR)
    fault_injection = metadata.get("faultInjection")
    if not isinstance(fault_injection, dict):
        fault_injection = {}
    test_mode = os.environ.get("VITALSERVER_ROOTFS_SMOKE_TEST_MODE") == "1" or (
        fault_injection.get("testMode") is True
    )
    fail_stage = os.environ.get("VITALSERVER_ROOTFS_SMOKE_FAIL_STAGE")
    if fail_stage is None and test_mode:
        metadata_fail_stage = fault_injection.get("failStage")
        fail_stage = metadata_fail_stage if isinstance(metadata_fail_stage, str) else ""
    fail_cleanup = os.environ.get("VITALSERVER_ROOTFS_SMOKE_FAIL_CLEANUP") == "1"
    if not fail_cleanup and test_mode:
        fail_cleanup = fault_injection.get("failCleanup") is True
    return RootfsSmokeContext(
        runtime_dir=RUNTIME_DIR,
        deploy_dir=DEPLOY_DIR,
        vital_files_mount=VITAL_FILES_MOUNT_POINT,
        manifest_path=RUNTIME_DIR / "rootfs-runtime-manifest.json",
        apt_plan_path=RUNTIME_DIR / "rootfs-apt-plan.json",
        apt_installed_path=RUNTIME_DIR / "rootfs-apt-installed.json",
        docker_image_bundle_path=DEPLOY_DIR
        / "docker-images"
        / "vitalserver-images.tar.gz",
        diagnostics_dir=RUNTIME_DIR / "rootfs-smoke-diagnostics",
        compose_project_name="vitalserver-rootfs-smoke",
        docker_smoke_image=os.environ.get(
            "VITALSERVER_DOCKER_SMOKE_IMAGE",
            "redis:3.2.12-alpine",
        ),
        local_docker_smoke_image="vitalserver-rootfs-smoke:local",
        run_id=rootfs_run_id(DEPLOY_DIR),
        test_mode=test_mode,
        fail_stage=fail_stage or "",
        fail_cleanup=fail_cleanup,
        minimum_disk_free_kib=int(
            os.environ.get(
                "VITALSERVER_ROOTFS_SMOKE_MINIMUM_DISK_FREE_KIB",
                str(MINIMUM_DISK_FREE_KIB),
            )
        ),
        runtime_data=read_runtime_data_contract(metadata),
        docker_daemon_config_path=Path("/etc/docker/daemon.json"),
        containerd_config_path=Path("/etc/containerd/config.toml"),
        rootfs_docker_store_path=Path("/var/lib/docker"),
        rootfs_containerd_store_path=Path("/var/lib/containerd"),
    )


def default_operations() -> RootfsSmokeOperations:
    return RootfsSmokeOperations(
        mount_runtime_share=mount_runtime_share,
        mount_vital_files_share=mount_vital_files_share,
        run=run_command,
        http_status=http_status,
        sleep=time.sleep,
    )


def run_rootfs_smoke(
    *,
    context: RootfsSmokeContext | None = None,
    operations: RootfsSmokeOperations | None = None,
) -> None:
    context = context or default_context()
    operations = operations or default_operations()
    operations.mount_runtime_share()
    operations.mount_vital_files_share()
    context.runtime_dir.mkdir(parents=True, exist_ok=True)
    context.vital_files_mount.mkdir(parents=True, exist_ok=True)
    prepare_container_bind_source_directories(context.runtime_dir)

    run = RootfsSmokeRun(context=context, operations=operations)
    run.write_manifest()
    failed = False
    diagnostics_collected = False

    try:
        execute_stage(run, "runtime-data-mount", runtime_data_mount)
        execute_stage(run, "runtime-data-configure", runtime_data_configure)
        execute_stage(run, "docker-service", docker_service)
        execute_stage(run, "runtime-version", runtime_version)
        execute_stage(run, "docker-image-load", docker_image_load)
        execute_stage(run, "docker-smoke", docker_smoke)
        execute_stage(run, "disk-space", disk_space)
        execute_stage(run, "compose-build", compose_build)
        execute_stage(run, "compose-up", compose_up)
        execute_stage(run, "edge-ready", edge_ready)
    except RootfsSmokeStageFailed:
        failed = True
        collect_diagnostics(run)
        diagnostics_collected = True
    finally:
        cleanup_passed = cleanup_compose(run)
        if not cleanup_passed:
            failed = True
        if failed and not diagnostics_collected:
            collect_diagnostics(run)
        run.write_manifest()

    if failed:
        raise SystemExit(1)


def docker_service(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    contract = require_runtime_data_contract(run)
    run_checked(
        run,
        ["systemctl", "start", "docker"],
        timeout_seconds=DOCKER_SMOKE_TIMEOUT_SECONDS,
    )
    completed = run_checked(
        run,
        ["docker", "info", "--format", "{{json .ServerVersion}}"],
        timeout_seconds=DOCKER_SMOKE_TIMEOUT_SECONDS,
    )
    root_dir = docker_root_dir(run)
    if root_dir != contract.docker_data_root:
        raise RuntimeError(
            "Docker data-root does not match runtime data contract: "
            f"expected={contract.docker_data_root} actual={root_dir}"
        )
    return "docker service is running", {
        "serverVersion": completed.stdout.strip(),
        "dockerDataRoot": root_dir,
    }


def docker_root_dir(run: RootfsSmokeRun) -> str:
    completed = run_checked(
        run,
        ["docker", "info", "--format", "{{json .DockerRootDir}}"],
        timeout_seconds=DOCKER_SMOKE_TIMEOUT_SECONDS,
    )
    text = completed.stdout.strip()
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"docker info returned invalid DockerRootDir JSON: {text}"
        ) from error
    if not isinstance(value, str) or not value.strip():
        raise RuntimeError(f"docker info returned invalid DockerRootDir: {text}")
    return value


def runtime_data_mount(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    contract = require_runtime_data_contract(run)

    mount_path = Path(contract.mount_path)
    mount_path.mkdir(parents=True, exist_ok=True)
    proof = mounted_runtime_data_proof(run, contract)
    if proof is None:
        source = runtime_data_device_source(run, contract)
        created_filesystem = False
        if source is None:
            source = provision_runtime_data_filesystem(run, contract)
            created_filesystem = True
        run_checked(
            run,
            ["mount", "-t", "ext4", source, contract.mount_path],
            timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
        )
        proof = mounted_runtime_data_proof(run, contract)
        if proof is None:
            run.runtime_data = {
                "status": RootfsSmokeStatus.FAILED.value,
                "message": "runtime data disk did not mount after provisioning",
                "mountPath": contract.mount_path,
                "filesystemLabel": contract.filesystem_label,
            }
            raise RuntimeError("runtime data disk did not mount after provisioning")
        proof["createdFilesystem"] = created_filesystem

    prepare_runtime_data_directories(contract)
    run.runtime_data = proof
    return "runtime data disk is mounted", proof


def require_runtime_data_contract(run: RootfsSmokeRun) -> RuntimeDataContract:
    contract = run.context.runtime_data
    if contract is None:
        run.runtime_data = {
            "status": RootfsSmokeStatus.FAILED.value,
            "message": "runtime data contract is missing or invalid",
        }
        raise RuntimeError("runtime data contract is missing or invalid")
    return contract


def runtime_data_configure(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    contract = require_runtime_data_contract(run)
    stop_docker_services(run)
    write_docker_daemon_config(run.context.docker_daemon_config_path, contract)
    write_containerd_config(run, contract)
    run_checked(
        run,
        ["systemctl", "daemon-reload"],
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    return "runtime data daemon configuration is written", {
        "dockerDaemonConfig": str(run.context.docker_daemon_config_path),
        "containerdConfig": str(run.context.containerd_config_path),
        "dockerDataRoot": contract.docker_data_root,
        "containerdRoot": contract.containerd_root,
    }


def stop_docker_services(run: RootfsSmokeRun) -> None:
    run_checked(
        run,
        ["systemctl", "stop", "docker.service", "docker.socket", "containerd.service"],
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )


def write_docker_daemon_config(path: Path, contract: RuntimeDataContract) -> None:
    if path.exists():
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise RuntimeError(
                f"Docker daemon config is unreadable: {path}: {error}"
            ) from error
        if not isinstance(document, dict):
            raise RuntimeError(f"Docker daemon config must be an object: {path}")
        existing = document.get("data-root")
        if existing is not None and existing != contract.docker_data_root:
            raise RuntimeError(
                "Docker daemon config has conflicting data-root: "
                f"path={path} expected={contract.docker_data_root} actual={existing}"
            )
    else:
        document = {}
    document["data-root"] = contract.docker_data_root
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def write_containerd_config(
    run: RootfsSmokeRun,
    contract: RuntimeDataContract,
) -> None:
    completed = run_checked(
        run,
        ["containerd", "config", "default"],
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    config = containerd_config_with_root(completed.stdout, contract.containerd_root)
    path = run.context.containerd_config_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(config, encoding="utf-8")


def containerd_config_with_root(config: str, root: str) -> str:
    if not config.strip():
        raise RuntimeError("containerd config default returned empty output")
    lines = config.splitlines()
    replaced = False
    for index, line in enumerate(lines):
        if line.startswith("root = "):
            lines[index] = f'root = "{root}"'
            replaced = True
            break
    if not replaced:
        raise RuntimeError("containerd default config is missing top-level root")
    return "\n".join(lines) + "\n"


def mounted_runtime_data_proof(
    run: RootfsSmokeRun,
    contract: RuntimeDataContract,
) -> dict[str, Any] | None:
    completed = run.operations.run(
        ["findmnt", "--json", "--mountpoint", contract.mount_path],
        check=False,
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        return None
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"findmnt returned invalid JSON: {error}") from error
    filesystems = document.get("filesystems")
    if not isinstance(filesystems, list) or not filesystems:
        return None
    mount = filesystems[0]
    if not isinstance(mount, dict):
        raise RuntimeError("findmnt filesystem entry is invalid")
    target = mount.get("target")
    source = mount.get("source")
    fstype = mount.get("fstype")
    if target != contract.mount_path:
        raise RuntimeError(
            "runtime data mount target mismatch: "
            f"expected={contract.mount_path} actual={target}"
        )
    if fstype not in ("ext4", "ext2", "ext3"):
        raise RuntimeError(
            "runtime data filesystem type is unsupported: "
            f"mountPath={contract.mount_path} fstype={fstype}"
        )
    if not isinstance(source, str) or not source.strip():
        raise RuntimeError(
            f"runtime data mount source is missing: mountPath={contract.mount_path}"
        )
    actual_label = filesystem_label(run, source)
    if actual_label is None:
        raise RuntimeError(
            "runtime data filesystem label is missing: "
            f"expected={contract.filesystem_label} source={source} "
            f"mountPath={contract.mount_path}"
        )
    if actual_label != contract.filesystem_label:
        raise RuntimeError(
            "runtime data mount source label does not match contract: "
            f"expected={contract.filesystem_label} actual={actual_label} "
            f"source={source}"
        )
    return {
        "status": RootfsSmokeStatus.PASSED.value,
        "message": "runtime data disk is mounted",
        "diskImageName": contract.disk_image_name,
        "diskSize": contract.disk_size,
        "filesystemLabel": contract.filesystem_label,
        "mountPath": contract.mount_path,
        "dockerDataRoot": contract.docker_data_root,
        "containerdRoot": contract.containerd_root,
        "source": source if isinstance(source, str) else "",
        "fstype": fstype,
        "createdFilesystem": False,
    }


def runtime_data_device_source(
    run: RootfsSmokeRun,
    contract: RuntimeDataContract,
) -> str | None:
    completed = run.operations.run(
        ["findfs", f"LABEL={contract.filesystem_label}"],
        check=False,
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    source = completed.stdout.strip()
    if completed.returncode == 0 and source:
        return source
    return None


def filesystem_label(run: RootfsSmokeRun, source: str) -> str | None:
    completed = run.operations.run(
        ["blkid", "-s", "LABEL", "-o", "value", source],
        check=False,
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    label = completed.stdout.strip()
    if completed.returncode == 0 and label:
        return label
    return None


def provision_runtime_data_filesystem(
    run: RootfsSmokeRun,
    contract: RuntimeDataContract,
) -> str:
    candidate = runtime_data_blank_disk_candidate(run, contract)
    run_checked(
        run,
        ["mkfs.ext4", "-F", "-L", contract.filesystem_label, candidate],
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    return candidate


def runtime_data_blank_disk_candidate(
    run: RootfsSmokeRun,
    contract: RuntimeDataContract,
) -> str:
    completed = run_checked(
        run,
        [
            "lsblk",
            "--json",
            "--bytes",
            "--output",
            "NAME,PATH,TYPE,SIZE,FSTYPE,MOUNTPOINTS",
        ],
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"lsblk returned invalid JSON: {error}") from error
    blockdevices = document.get("blockdevices")
    if not isinstance(blockdevices, list):
        raise RuntimeError("lsblk output is missing blockdevices")
    expected_size = size_to_bytes(contract.disk_size)
    candidates = [
        str(device["path"])
        for device in blockdevices
        if runtime_data_blank_disk_matches(device, expected_size)
    ]
    if len(candidates) != 1:
        raise RuntimeError(
            "runtime data blank disk candidate count is invalid: "
            f"expected=1 actual={len(candidates)} candidates={candidates}"
        )
    return candidates[0]


def runtime_data_blank_disk_matches(device: object, expected_size: int) -> bool:
    if not isinstance(device, dict):
        return False
    mountpoints = device.get("mountpoints")
    children = device.get("children")
    return (
        device.get("type") == "disk"
        and isinstance(device.get("path"), str)
        and device.get("size") == expected_size
        and not device.get("fstype")
        and (not isinstance(mountpoints, list) or not any(mountpoints))
        and not children
    )


def runtime_version(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    run.runtime_versions = collect_runtime_versions(run.operations)
    return "runtime versions collected", run.runtime_versions


def docker_image_load(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    bundle = run.context.docker_image_bundle_path
    if not bundle.is_file():
        raise RuntimeError(f"missing Docker image bundle: {bundle}")
    contract = read_docker_images_contract(run.context.deploy_dir)
    bundle_bytes = bundle.stat().st_size
    bundle_sha256 = sha256_file(bundle)
    guest_architecture = guest_machine_architecture(run)
    expected_architectures = expected_guest_architectures(contract["platform"])
    details = {
        "bundle": str(bundle),
        "bundleBytes": bundle_bytes,
        "bundleSha256": bundle_sha256,
        "platform": contract["platform"],
        "guestArchitecture": guest_architecture,
        "expectedGuestArchitectures": expected_architectures,
        "timeoutSeconds": DOCKER_IMAGE_LOAD_TIMEOUT_SECONDS,
    }
    if guest_architecture not in expected_architectures:
        run.docker_images = {
            "status": RootfsSmokeStatus.FAILED.value,
            "message": "Docker image platform does not match guest architecture",
            **details,
        }
        raise RuntimeError(
            "Docker image platform does not match guest architecture: "
            f"platform={contract['platform']} guest={guest_architecture} "
            f"expected={expected_architectures}"
        )
    update_current_stage(
        run,
        message="loading Docker image bundle",
        details=details,
    )
    run_checked(
        run,
        ["docker", "load", "-i", str(bundle)],
        timeout_seconds=DOCKER_IMAGE_LOAD_TIMEOUT_SECONDS,
    )
    run.docker_images = {
        "status": RootfsSmokeStatus.PASSED.value,
        "message": "Docker image bundle matched guest architecture and loaded",
        **details,
    }
    return "Docker image bundle loaded", details


def execute_stage(
    run: RootfsSmokeRun,
    name: str,
    action: Callable[[RootfsSmokeRun], tuple[str, dict[str, Any]]],
) -> None:
    started_at = utc_now()
    run.stages.append(
        SmokeStageResult(
            name=name,
            status=RootfsSmokeStatus.RUNNING,
            started_at=started_at,
            completed_at="",
            message="stage is running",
        )
    )
    run.write_manifest()
    try:
        fail_stage_if_requested(run, name)
        message, details = action(run)
    except subprocess.TimeoutExpired as error:
        details = dict(run.stages[-1].details)
        details["command"] = error.cmd
        run.stages[-1] = SmokeStageResult(
            name=name,
            status=RootfsSmokeStatus.TIMEOUT,
            started_at=started_at,
            completed_at=utc_now(),
            message=f"stage timed out after {error.timeout:g}s",
            details=details,
        )
        run.write_manifest()
        raise RootfsSmokeStageFailed(name) from error
    except Exception as error:
        run.stages[-1] = SmokeStageResult(
            name=name,
            status=RootfsSmokeStatus.FAILED,
            started_at=started_at,
            completed_at=utc_now(),
            message=str(error),
        )
        run.write_manifest()
        raise RootfsSmokeStageFailed(name) from error

    run.stages[-1] = SmokeStageResult(
        name=name,
        status=RootfsSmokeStatus.PASSED,
        started_at=started_at,
        completed_at=utc_now(),
        message=message,
        details=details,
    )
    run.write_manifest()


def update_current_stage(
    run: RootfsSmokeRun,
    *,
    message: str,
    details: dict[str, Any],
) -> None:
    if not run.stages:
        return
    current = run.stages[-1]
    run.stages[-1] = SmokeStageResult(
        name=current.name,
        status=current.status,
        started_at=current.started_at,
        completed_at=current.completed_at,
        message=message,
        details=details,
    )
    run.write_manifest()


def docker_smoke(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    smoke_image = run.context.docker_smoke_image
    smoke_command = ["true"]
    temporary_image = False
    inspect = run.operations.run(
        ["docker", "image", "inspect", smoke_image],
        check=False,
    )
    if inspect.returncode != 0:
        smoke_image = build_local_docker_smoke_image(run)
        smoke_command = ["/bin/busybox", "true"]
        temporary_image = True

    try:
        run_checked(
            run,
            [
                "docker",
                "run",
                "--rm",
                "--network",
                "none",
                "--security-opt",
                DOCKER_SECCOMP_SECURITY_OPT,
                smoke_image,
                *smoke_command,
            ],
            timeout_seconds=DOCKER_SMOKE_TIMEOUT_SECONDS,
        )
    finally:
        if temporary_image:
            run.operations.run(
                ["docker", "image", "rm", "-f", smoke_image],
                check=False,
            )

    return "docker runtime smoke passed", {"image": smoke_image}


def disk_space(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    contract = require_runtime_data_contract(run)
    paths = [
        "/",
        contract.docker_data_root,
        contract.containerd_root,
        str(run.context.vital_files_mount),
    ]
    results: list[dict[str, Any]] = []
    for path in paths:
        completed = run_checked(
            run,
            ["df", "-Pk", path],
            timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
        )
        free_kib = parse_df_available_kib(completed.stdout, path)
        inode_completed = run_checked(
            run,
            ["df", "-Pki", path],
            timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
        )
        free_inodes = parse_df_available_inodes(inode_completed.stdout, path)
        passed = free_kib >= run.context.minimum_disk_free_kib
        inode_passed = free_inodes >= MINIMUM_DISK_FREE_INODES
        results.append(
            {
                "path": path,
                "availableKiB": free_kib,
                "minimumKiB": run.context.minimum_disk_free_kib,
                "availableInodes": free_inodes,
                "minimumInodes": MINIMUM_DISK_FREE_INODES,
                "passed": passed and inode_passed,
            }
        )
        if not passed:
            raise RuntimeError(
                "insufficient rootfs disk space: "
                f"path={path} availableKiB={free_kib} "
                f"minimumKiB={run.context.minimum_disk_free_kib}"
            )
        if not inode_passed:
            raise RuntimeError(
                "insufficient rootfs free inodes: "
                f"path={path} availableInodes={free_inodes} "
                f"minimumInodes={MINIMUM_DISK_FREE_INODES}"
            )
    return "rootfs and runtime data disk space check passed", {"filesystems": results}


def parse_df_available_kib(output: str, path: str) -> int:
    lines = [line for line in output.splitlines() if line.strip()]
    if len(lines) < 2:
        raise RuntimeError(f"df output missing filesystem row for {path}")
    columns = lines[-1].split()
    if len(columns) < 4:
        raise RuntimeError(f"df output malformed for {path}: {lines[-1]}")
    try:
        return int(columns[3])
    except ValueError as error:
        raise RuntimeError(
            f"df output available column is not an integer for {path}: {columns[3]}"
        ) from error


def parse_df_available_inodes(output: str, path: str) -> int:
    lines = [line for line in output.splitlines() if line.strip()]
    if len(lines) < 2:
        raise RuntimeError(f"df inode output missing filesystem row for {path}")
    columns = lines[-1].split()
    if len(columns) < 4:
        raise RuntimeError(f"df inode output malformed for {path}: {lines[-1]}")
    try:
        return int(columns[3])
    except ValueError as error:
        raise RuntimeError(
            f"df inode output free column is not an integer for {path}: {columns[3]}"
        ) from error


def build_local_docker_smoke_image(run: RootfsSmokeRun) -> str:
    with tempfile.TemporaryDirectory() as temporary:
        workdir = Path(temporary)
        rootfs = workdir / "rootfs"
        tarball = workdir / "rootfs.tar"
        rootfs.mkdir()
        (rootfs / "bin").mkdir()
        shutil.copy2("/bin/busybox", rootfs / "bin/busybox")
        with tarfile.open(tarball, "w") as archive:
            archive.add(rootfs, arcname=".")
        run_checked(
            run,
            ["docker", "import", str(tarball), run.context.local_docker_smoke_image],
            timeout_seconds=DOCKER_SMOKE_TIMEOUT_SECONDS,
        )
    return run.context.local_docker_smoke_image


def compose_build(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    run_checked(
        run,
        compose_command(
            run,
            [
                "build",
                "app",
                "recorder-recovery",
                "recorder-ingress",
                "vitaldb-observer",
            ],
        ),
        timeout_seconds=COMPOSE_BUILD_TIMEOUT_SECONDS,
    )
    return "compose images built", {}


def compose_up(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    run_checked(
        run,
        compose_command(run, ["up", "--pull", "never", "--no-build", "-d", "redis"]),
        timeout_seconds=COMPOSE_UP_TIMEOUT_SECONDS,
    )
    run_checked(
        run,
        compose_command(
            run,
            [
                "up",
                "--pull",
                "never",
                "--no-build",
                "-d",
                "app",
                "recorder-recovery",
                "recorder-ingress",
                "vitaldb-observer",
                "redis-ui",
                "swagger-ui",
            ],
        ),
        timeout_seconds=COMPOSE_UP_TIMEOUT_SECONDS,
    )
    run_checked(
        run,
        compose_command(run, ["up", "--pull", "never", "--no-build", "-d", "edge"]),
        timeout_seconds=COMPOSE_UP_TIMEOUT_SECONDS,
    )
    return "compose stack started", {}


def edge_ready(run: RootfsSmokeRun) -> tuple[str, dict[str, Any]]:
    deadline = time.monotonic() + EDGE_READY_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        try:
            status = run.operations.http_status(
                "http://127.0.0.1/ready",
                EDGE_READY_HTTP_TIMEOUT_SECONDS,
            )
        except (OSError, TimeoutError, urllib.error.URLError):
            status = 0
        if 200 <= status < 300:
            return "edge readiness endpoint returned success", {
                "httpStatus": status,
                "services": compose_services(run),
            }
        run.operations.sleep(EDGE_READY_POLL_SECONDS)
    raise subprocess.TimeoutExpired(
        ["http", "GET", "http://127.0.0.1/ready"],
        EDGE_READY_TIMEOUT_SECONDS,
    )


def cleanup_compose(run: RootfsSmokeRun) -> bool:
    if run.context.test_mode and run.context.fail_cleanup:
        run.cleanup = {
            "status": RootfsSmokeStatus.CLEANUP_FAILED.value,
            "message": "test fault injected cleanup failure",
        }
        return False
    commands = [
        (
            "compose-down",
            compose_command(run, ["down", "-v", "--remove-orphans", "--rmi", "all"]),
            COMPOSE_CLEANUP_TIMEOUT_SECONDS,
        ),
        (
            "docker-builder-prune",
            ["docker", "builder", "prune", "--all", "--force"],
            DOCKER_PRUNE_TIMEOUT_SECONDS,
        ),
        (
            "docker-system-prune",
            ["docker", "system", "prune", "--all", "--force", "--volumes"],
            DOCKER_PRUNE_TIMEOUT_SECONDS,
        ),
    ]
    results: list[dict[str, Any]] = []
    for name, command, timeout_seconds in commands:
        completed = run.operations.run(
            command,
            check=False,
            timeout_seconds=timeout_seconds,
        )
        results.append(cleanup_command_result(name, completed))
        if completed.returncode != 0:
            run.cleanup = {
                "status": RootfsSmokeStatus.CLEANUP_FAILED.value,
                "message": f"{name} failed: {command_output(completed)}",
                "commands": results,
            }
            return False
    verification = verify_docker_store_is_empty(run)
    results.extend(verification)
    rootfs_store_verification = verify_rootfs_runtime_stores_are_empty(run)
    results.extend(rootfs_store_verification)
    failed_verification = next(
        (
            result
            for result in [*verification, *rootfs_store_verification]
            if result["status"] != "passed"
        ),
        None,
    )
    if failed_verification is not None:
        run.cleanup = {
            "status": RootfsSmokeStatus.CLEANUP_FAILED.value,
            "message": (
                f"{failed_verification['name']} failed: "
                f"{failed_verification['message']}"
            ),
            "commands": results,
        }
        return False
    run.cleanup = {
        "status": RootfsSmokeStatus.PASSED.value,
        "message": "compose stack and Docker store cleanup completed",
        "commands": results,
    }
    return True


def cleanup_command_result(
    name: str,
    completed: subprocess.CompletedProcess[str],
) -> dict[str, Any]:
    return {
        "name": name,
        "status": "passed" if completed.returncode == 0 else "failed",
        "exitCode": completed.returncode,
        "message": command_output(completed),
    }


def verify_docker_store_is_empty(run: RootfsSmokeRun) -> list[dict[str, Any]]:
    checks = [
        ("docker-containers-empty", ["docker", "ps", "--all", "--quiet"]),
        ("docker-images-empty", ["docker", "images", "--all", "--quiet"]),
        ("docker-volumes-empty", ["docker", "volume", "ls", "--quiet"]),
    ]
    results: list[dict[str, Any]] = []
    for name, command in checks:
        completed = run.operations.run(
            command,
            check=False,
            timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
        )
        output = completed.stdout.strip()
        if completed.returncode != 0:
            status = "failed"
            message = command_output(completed)
        elif output:
            status = "failed"
            message = output
        else:
            status = "passed"
            message = ""
        results.append(
            {
                "name": name,
                "status": status,
                "exitCode": completed.returncode,
                "message": message,
            }
        )
    return results


def verify_rootfs_runtime_stores_are_empty(run: RootfsSmokeRun) -> list[dict[str, Any]]:
    return [
        directory_empty_result(
            "rootfs-docker-store-empty",
            run.context.rootfs_docker_store_path,
        ),
        directory_empty_result(
            "rootfs-containerd-store-empty",
            run.context.rootfs_containerd_store_path,
        ),
    ]


def directory_empty_result(name: str, path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "name": name,
            "status": "passed",
            "exitCode": 0,
            "message": "missing",
            "path": str(path),
        }
    if not path.is_dir():
        return {
            "name": name,
            "status": "failed",
            "exitCode": 1,
            "message": "path is not a directory",
            "path": str(path),
        }
    entries = sorted(entry.name for entry in path.iterdir())
    if entries:
        return {
            "name": name,
            "status": "failed",
            "exitCode": 1,
            "message": ",".join(entries),
            "path": str(path),
        }
    return {
        "name": name,
        "status": "passed",
        "exitCode": 0,
        "message": "",
        "path": str(path),
    }


def compose_services(run: RootfsSmokeRun) -> list[dict[str, Any]]:
    completed = run.operations.run(
        compose_command(run, ["ps", "--format", "json"]),
        check=False,
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    if completed.returncode != 0:
        return []
    text = completed.stdout.strip()
    if not text:
        return []
    try:
        parsed = json.loads(text)
        if isinstance(parsed, list):
            return [item for item in parsed if isinstance(item, dict)]
        if isinstance(parsed, dict):
            return [parsed]
    except json.JSONDecodeError:
        services: list[dict[str, Any]] = []
        for line in text.splitlines():
            try:
                parsed_line = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(parsed_line, dict):
                services.append(parsed_line)
        return services
    return []


def collect_diagnostics(run: RootfsSmokeRun) -> None:
    run.context.diagnostics_dir.mkdir(parents=True, exist_ok=True)
    diagnostics = {
        "docker-version.txt": ["docker", "--version"],
        "docker-info.txt": ["docker", "info"],
        "compose-ps.json": compose_command(run, ["ps", "--format", "json"]),
        "compose-logs.txt": compose_command(run, ["logs", "--tail=300"]),
        "journal-cloud-final.txt": [
            "journalctl",
            "-u",
            "cloud-final",
            "--no-pager",
            "-n",
            "300",
        ],
        "journal-docker.txt": [
            "journalctl",
            "-u",
            "docker",
            "--no-pager",
            "-n",
            "300",
        ],
        "df.txt": ["df", "-h"],
    }
    for name, command in diagnostics.items():
        completed = run.operations.run(
            command,
            check=False,
            timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
        )
        (run.context.diagnostics_dir / name).write_text(
            command_output(completed),
            encoding="utf-8",
        )

    completed = run.operations.run(
        ["dmesg", "--ctime"],
        check=False,
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    dmesg_tail = "\n".join(command_output(completed).splitlines()[-300:])
    (run.context.diagnostics_dir / "dmesg-tail.txt").write_text(
        dmesg_tail + "\n",
        encoding="utf-8",
    )
    (run.context.diagnostics_dir / "manifest.partial.json").write_text(
        json.dumps(run.as_json(), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def collect_runtime_versions(operations: RootfsSmokeOperations) -> dict[str, str]:
    commands = {
        "kernel": ["uname", "-r"],
        "docker": ["docker", "--version"],
        "containerd": ["containerd", "--version"],
        "runc": ["runc", "--version"],
        "compose": ["docker", "compose", "version"],
    }
    versions: dict[str, str] = {}
    for key, command in commands.items():
        completed = operations.run(command, check=False)
        versions[key] = (
            completed.stdout.splitlines()[0].strip() if completed.stdout else ""
        )
    return versions


def read_ubuntu_metadata(deploy_dir: Path) -> dict[str, str]:
    document = read_rootfs_input_document(deploy_dir)
    if not document:
        return {
            "metadataStatus": "missing",
            "aptSnapshot": "",
            "baseUrl": "",
            "cacheKey": "",
        }
    ubuntu = document.get("ubuntu")
    if not isinstance(ubuntu, dict):
        return {
            "metadataStatus": "invalid",
            "aptSnapshot": "",
            "baseUrl": "",
            "cacheKey": "",
        }
    base_url = ubuntu.get("baseUrl")
    cache_key = ubuntu.get("cacheKey")
    apt_snapshot = ubuntu.get("aptSnapshot")
    return {
        "metadataStatus": "loaded",
        "aptSnapshot": apt_snapshot if isinstance(apt_snapshot, str) else "",
        "baseUrl": base_url if isinstance(base_url, str) else "",
        "cacheKey": cache_key if isinstance(cache_key, str) else "",
    }


def read_runtime_data_contract(document: dict[str, Any]) -> RuntimeDataContract | None:
    runtime_data = document.get("runtimeData")
    if not isinstance(runtime_data, dict):
        return None
    values: dict[str, str] = {}
    for key in (
        "diskImageName",
        "diskSize",
        "filesystemLabel",
        "mountPath",
        "dockerDataRoot",
        "containerdRoot",
    ):
        value = runtime_data.get(key)
        if not isinstance(value, str) or not value.strip():
            return None
        values[key] = value
    return RuntimeDataContract(
        disk_image_name=values["diskImageName"],
        disk_size=values["diskSize"],
        filesystem_label=values["filesystemLabel"],
        mount_path=values["mountPath"],
        docker_data_root=values["dockerDataRoot"],
        containerd_root=values["containerdRoot"],
    )


def read_docker_images_contract(deploy_dir: Path) -> dict[str, str]:
    document = read_rootfs_input_document(deploy_dir)
    docker_images = document.get("dockerImages")
    if not isinstance(docker_images, dict):
        raise RuntimeError("rootfs input metadata is missing dockerImages contract")
    platform = docker_images.get("platform")
    if not isinstance(platform, str) or not platform.strip():
        raise RuntimeError("rootfs input metadata has invalid dockerImages.platform")
    return {"platform": platform}


def guest_machine_architecture(run: RootfsSmokeRun) -> str:
    completed = run_checked(
        run,
        ["uname", "-m"],
        timeout_seconds=DIAGNOSTIC_COMMAND_TIMEOUT_SECONDS,
    )
    value = completed.stdout.strip()
    if not value:
        raise RuntimeError("guest architecture probe returned empty output")
    return value


def expected_guest_architectures(platform: str) -> list[str]:
    mapping = {
        "linux/arm64": ["aarch64", "arm64"],
        "linux/amd64": ["x86_64", "amd64"],
    }
    expected = mapping.get(platform)
    if expected is None:
        raise RuntimeError(f"unsupported Docker image platform: {platform}")
    return expected


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_apt_plan(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {
            "schemaVersion": 1,
            "status": "missing",
            "path": str(path),
            "blockedUpgrades": [],
        }
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "schemaVersion": 1,
            "status": "invalid",
            "path": str(path),
            "error": str(error),
            "blockedUpgrades": [],
        }
    if not isinstance(document, dict):
        return {
            "schemaVersion": 1,
            "status": "invalid",
            "path": str(path),
            "error": "expected object",
            "blockedUpgrades": [],
        }
    return document


def read_apt_installed(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {
            "schemaVersion": 1,
            "status": "missing",
            "path": str(path),
            "packages": {},
        }
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return {
            "schemaVersion": 1,
            "status": "invalid",
            "path": str(path),
            "error": str(error),
            "packages": {},
        }
    if not isinstance(document, dict):
        return {
            "schemaVersion": 1,
            "status": "invalid",
            "path": str(path),
            "error": "expected object",
            "packages": {},
        }
    return document


def rootfs_run_id(deploy_dir: Path) -> str:
    document = read_rootfs_input_document(deploy_dir)
    run_id = document.get("runId")
    if isinstance(run_id, str) and run_id.strip():
        return run_id
    return str(uuid.uuid4())


def read_rootfs_input_document(deploy_dir: Path) -> dict[str, Any]:
    metadata = deploy_dir / "build-metadata" / "rootfs-input.json"
    if not metadata.is_file():
        return {}
    try:
        document = json.loads(metadata.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"ubuntu": None}
    return document if isinstance(document, dict) else {"ubuntu": None}


def size_to_bytes(value: str) -> int:
    suffix = value[-1:].lower()
    unit = suffix if suffix in ("k", "m", "g") else ""
    number_text = value[:-1] if unit else value
    try:
        number = int(number_text)
    except ValueError as error:
        raise RuntimeError(f"invalid size value: {value}") from error
    multipliers = {
        "": 1,
        "k": 1024,
        "m": 1024 * 1024,
        "g": 1024 * 1024 * 1024,
    }
    if unit not in multipliers:
        raise RuntimeError(f"invalid size unit: {value}")
    return number * multipliers[unit]


def fail_stage_if_requested(run: RootfsSmokeRun, name: str) -> None:
    if not run.context.test_mode:
        return
    if run.context.fail_stage != name:
        return
    if name == "edge-ready":
        raise subprocess.TimeoutExpired(
            ["fault-injection", name],
            EDGE_READY_TIMEOUT_SECONDS,
        )
    raise RuntimeError(f"test fault injected stage failure: {name}")


def compose_command(run: RootfsSmokeRun, arguments: list[str]) -> list[str]:
    return [
        "docker",
        "compose",
        "--project-name",
        run.context.compose_project_name,
        "-f",
        str(run.context.deploy_dir / "compose.yaml"),
        *arguments,
    ]


def run_checked(
    run: RootfsSmokeRun,
    arguments: list[str],
    *,
    timeout_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    completed = run.operations.run(
        arguments,
        check=False,
        timeout_seconds=timeout_seconds,
    )
    if completed.returncode != 0:
        raise RootfsSmokeCommandFailed(completed)
    return completed


def run_command(
    arguments: list[str],
    *,
    check: bool = True,
    timeout_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        arguments,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
    )
    if check and completed.returncode != 0:
        raise RootfsSmokeCommandFailed(completed)
    return completed


def http_status(url: str, timeout_seconds: float) -> int:
    with urllib.request.urlopen(url, timeout=timeout_seconds) as response:
        return int(response.status)


def command_output(completed: subprocess.CompletedProcess[str]) -> str:
    stdout = completed.stdout or ""
    stderr = completed.stderr or ""
    return stdout + (("\n" + stderr) if stderr else "")
