from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path

from tirosh_guest_tools.application.runtime_data_prepare import prepare_runtime_data
from tirosh_guest_tools.contracts import RuntimeFileName, RuntimeService
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

BOOTSTRAP_RESULT = RUNTIME_DIR / RuntimeFileName.BOOTSTRAP_RESULT.value
DOCKER_SMOKE_IMAGE = "redis:3.2.12-alpine"
EDGE_READY_URL = "http://127.0.0.1/ready"
EDGE_READY_TIMEOUT_SECONDS = 600.0
EDGE_READY_POLL_SECONDS = 3.0
EDGE_READY_HTTP_TIMEOUT_SECONDS = 5.0


class GuestBootstrapStep(StrEnum):
    MOUNT_SHARES = "mount-shares"
    WRITE_RUNNING_RESULT = "write-running-result"
    VALIDATE_DEPLOY_CONTRACT = "validate-deploy-contract"
    EXPAND_ROOT_FILESYSTEM = "expand-root-filesystem"
    REQUIRE_RUNTIME_PACKAGES = "require-runtime-packages"
    INSTALL_RUNTIME_FILES = "install-runtime-files"
    PREPARE_RUNTIME_DATA = "prepare-runtime-data"
    WRITE_INITIAL_RUNTIME_STATE = "write-initial-runtime-state"
    START_DOCKER = "start-docker"
    START_AVAHI = "start-avahi"
    START_GUEST_BACKGROUND_SERVICES = "start-guest-background-services"
    PREPARE_SHARED_DIRECTORIES = "prepare-shared-directories"
    LOAD_DOCKER_IMAGES = "load-docker-images"
    RUN_DOCKER_SMOKE = "run-docker-smoke"
    CLEANUP_DOCKER_CACHE = "cleanup-docker-cache"
    BUILD_MISSING_IMAGES = "build-missing-images"
    START_COMPOSE = "start-compose"
    START_CONTAINER_LOGS = "start-container-logs"
    WAIT_EDGE_READY = "wait-edge-ready"
    RESTART_RUNTIME_STATE = "restart-runtime-state"
    WRITE_COMPLETED_RESULT = "write-completed-result"
    START_OPTIONAL_TESTKIT = "start-optional-testkit"
    RUN_RUNTIME_BOOT_SMOKE = "run-runtime-boot-smoke"


@dataclass
class GuestBootstrapState:
    completed_steps: list[GuestBootstrapStep] = field(default_factory=list)
    result_terminal: bool = False

    def complete(self, step: GuestBootstrapStep) -> None:
        self.completed_steps.append(step)

    def has_completed(self, step: GuestBootstrapStep) -> bool:
        return step in self.completed_steps

    def require_completed(
        self,
        required: GuestBootstrapStep,
        before: GuestBootstrapStep,
    ) -> None:
        if not self.has_completed(required):
            raise RuntimeError(
                "invalid guest bootstrap order: "
                f"{before.value} requires {required.value}"
            )


@dataclass(frozen=True)
class GuestBootstrapContext:
    deploy_dir: Path = DEPLOY_DIR
    runtime_dir: Path = RUNTIME_DIR
    vital_files_mount: Path = VITAL_FILES_MOUNT_POINT
    bootstrap_result: Path = BOOTSTRAP_RESULT
    docker_smoke_image: str = DOCKER_SMOKE_IMAGE
    edge_ready_url: str = EDGE_READY_URL
    edge_ready_timeout_seconds: float = EDGE_READY_TIMEOUT_SECONDS
    edge_ready_poll_seconds: float = EDGE_READY_POLL_SECONDS
    edge_ready_http_timeout_seconds: float = EDGE_READY_HTTP_TIMEOUT_SECONDS


@dataclass(frozen=True)
class GuestBootstrapOperations:
    run: Callable[..., subprocess.CompletedProcess[str]]
    output: Callable[[list[str]], str]
    http_status: Callable[[str, float], int]
    sleep: Callable[[float], None]
    now: Callable[[], str]
    boot_id: Callable[[], str]
    mount_runtime_share: Callable[[], None]
    mount_vital_files_share: Callable[[], None]
    install_guest_tools_runtime: Callable[[], None]
    prepare_runtime_data: Callable[[], None]


def default_operations() -> GuestBootstrapOperations:
    return GuestBootstrapOperations(
        run=run_command,
        output=command_output,
        http_status=http_status,
        sleep=time.sleep,
        now=utc_now,
        boot_id=read_boot_id,
        mount_runtime_share=mount_runtime_share,
        mount_vital_files_share=mount_vital_files_share,
        install_guest_tools_runtime=install_guest_tools_runtime,
        prepare_runtime_data=prepare_runtime_data,
    )


def run_guest_bootstrap(
    *,
    context: GuestBootstrapContext | None = None,
    operations: GuestBootstrapOperations | None = None,
) -> None:
    workflow = GuestBootstrapWorkflow(
        context=context or GuestBootstrapContext(),
        operations=operations or default_operations(),
    )
    workflow.run()


class GuestBootstrapWorkflow:
    def __init__(
        self,
        *,
        context: GuestBootstrapContext,
        operations: GuestBootstrapOperations,
    ) -> None:
        self.context = context
        self.operations = operations
        self.state = GuestBootstrapState()

    def run(self) -> None:
        try:
            for step, action in self.plan():
                self.execute(step, action)
        except Exception:
            if not self.state.result_terminal:
                self.write_bootstrap_result(
                    "failed",
                    "Guest bootstrap failed before completion.",
                    ("guest-bootstrap-failed",),
                )
            raise

    def plan(self) -> list[tuple[GuestBootstrapStep, Callable[[], None]]]:
        return [
            (GuestBootstrapStep.MOUNT_SHARES, self.mount_shares),
            (GuestBootstrapStep.WRITE_RUNNING_RESULT, self.write_running_result),
            (GuestBootstrapStep.VALIDATE_DEPLOY_CONTRACT, self.require_deploy_bundle),
            (GuestBootstrapStep.EXPAND_ROOT_FILESYSTEM, self.expand_root_filesystem),
            (
                GuestBootstrapStep.REQUIRE_RUNTIME_PACKAGES,
                self.require_runtime_packages,
            ),
            (GuestBootstrapStep.INSTALL_RUNTIME_FILES, self.install_runtime_files),
            (GuestBootstrapStep.PREPARE_RUNTIME_DATA, self.prepare_runtime_data),
            (
                GuestBootstrapStep.WRITE_INITIAL_RUNTIME_STATE,
                self.write_initial_runtime_state,
            ),
            (GuestBootstrapStep.START_DOCKER, self.start_docker),
            (GuestBootstrapStep.START_AVAHI, self.start_avahi),
            (
                GuestBootstrapStep.START_GUEST_BACKGROUND_SERVICES,
                self.start_guest_background_services,
            ),
            (
                GuestBootstrapStep.PREPARE_SHARED_DIRECTORIES,
                self.prepare_shared_directories,
            ),
            (GuestBootstrapStep.LOAD_DOCKER_IMAGES, self.load_bundled_docker_images),
            (GuestBootstrapStep.RUN_DOCKER_SMOKE, self.run_docker_runtime_smoke),
            (GuestBootstrapStep.CLEANUP_DOCKER_CACHE, self.cleanup_docker_cache),
            (GuestBootstrapStep.BUILD_MISSING_IMAGES, self.build_missing_images),
            (GuestBootstrapStep.START_COMPOSE, self.start_compose),
            (GuestBootstrapStep.START_CONTAINER_LOGS, self.start_container_logs),
            (GuestBootstrapStep.WAIT_EDGE_READY, self.wait_for_vitalserver_edge),
            (GuestBootstrapStep.RESTART_RUNTIME_STATE, self.restart_runtime_state),
            (GuestBootstrapStep.WRITE_COMPLETED_RESULT, self.write_completed_result),
            (GuestBootstrapStep.START_OPTIONAL_TESTKIT, self.start_optional_testkit),
            (
                GuestBootstrapStep.RUN_RUNTIME_BOOT_SMOKE,
                self.run_runtime_boot_smoke_if_requested,
            ),
        ]

    def execute(self, step: GuestBootstrapStep, action: Callable[[], None]) -> None:
        action()
        self.state.complete(step)

    def mount_shares(self) -> None:
        self.operations.mount_runtime_share()
        self.operations.mount_vital_files_share()

    def write_running_result(self) -> None:
        self.write_bootstrap_result("running", "Guest bootstrap is running.", ())

    def write_completed_result(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.WAIT_EDGE_READY,
            GuestBootstrapStep.WRITE_COMPLETED_RESULT,
        )
        self.write_bootstrap_result("completed", "Guest bootstrap completed.", ())
        print("VitalServer edge is ready on this VM at port 80.")

    def write_bootstrap_result(
        self,
        status: str,
        message: str,
        reason_codes: tuple[str, ...],
    ) -> None:
        boot_id = self.operations.boot_id()
        write_json(
            self.context.bootstrap_result,
            {
                "bootID": boot_id,
                "message": message,
                "operation": "bootstrap",
                "reasonCodes": list(reason_codes),
                "schemaVersion": 3,
                "status": status,
                "updatedAt": self.operations.now(),
            },
        )
        if status in {"completed", "failed"}:
            self.state.result_terminal = True

    def require_deploy_bundle(self) -> None:
        required_files = (
            self.context.deploy_dir / RuntimeFileName.COMPOSE.value,
            self.context.deploy_dir / RuntimeFileName.RUNTIME_CONFIG.value,
        )
        missing = [str(path) for path in required_files if not path.is_file()]
        if missing:
            raise RuntimeError("missing deploy bundle files: " + ", ".join(missing))

    def expand_root_filesystem(self) -> None:
        root_source = self.command_text(["findmnt", "-n", "-o", "SOURCE", "/"])
        parent_device = self.command_text(["lsblk", "-no", "PKNAME", root_source])
        partition_number = self.command_text(["lsblk", "-no", "PARTNUM", root_source])
        filesystem_type = self.command_text(["findmnt", "-n", "-o", "FSTYPE", "/"])
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
            self.operations.run(
                ["growpart", f"/dev/{parent_device}", partition_number],
                check=False,
            )
        else:
            print("warning: growpart is not available; root partition may stay small")
        if filesystem_type in {"ext2", "ext3", "ext4"}:
            self.operations.run(["resize2fs", root_source], check=False)
        elif filesystem_type == "xfs":
            self.operations.run(["xfs_growfs", "/"], check=False)
        else:
            print(f"warning: unsupported root filesystem for resize: {filesystem_type}")
        self.operations.run(["df", "-h", "/"])

    def require_runtime_packages(self) -> None:
        missing = runtime_package_missing_commands(self.operations)
        if not missing:
            print("Runtime packages are available in the air-gapped rootfs.")
            return
        self.write_bootstrap_result(
            "failed",
            "Missing runtime packages.",
            ("guest-bootstrap-missing-runtime-packages",),
        )
        raise RuntimeError("missing runtime packages: " + ", ".join(missing))

    def install_runtime_files(self) -> None:
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
        self.operations.run(["install", "-d", "-m", "0755", "/etc/tirosh"])
        for name in command_names:
            self.operations.run(
                [
                    "install",
                    "-m",
                    "0755",
                    str(self.context.deploy_dir / "bin" / name),
                    f"/usr/local/bin/{name}",
                ]
            )
        self.operations.install_guest_tools_runtime()
        for name in service_files:
            self.operations.run(
                [
                    "install",
                    "-m",
                    "0644",
                    str(self.context.deploy_dir / "systemd" / name),
                    f"/etc/systemd/system/{name}",
                ]
            )
        self.systemctl("daemon-reload")
        for service in (
            "tirosh-vitalserver-redis-backup.path",
            "tirosh-vitalserver-redis-restore.path",
            "tirosh-vitalserver-repair-datastore.path",
            "tirosh-vitalserver-activate-update.path",
            "tirosh-vitalserver-prepare-update-shutdown.path",
        ):
            self.systemctl("disable", "--now", service, check=False)
        for service in (
            RuntimeService.RUNTIME_STATE.value,
            RuntimeService.COMPOSE.value,
            RuntimeService.TESTKIT.value,
            RuntimeService.CONTAINER_LOGS.value,
            RuntimeService.REDIS_BACKUP_TIMER.value,
            RuntimeService.COMMAND_POLLER.value,
            "tirosh-guest-observability.service",
        ):
            self.systemctl("enable", service)

    def prepare_runtime_data(self) -> None:
        self.operations.prepare_runtime_data()

    def write_initial_runtime_state(self) -> None:
        self.operations.run(["/usr/local/bin/tirosh-runtime-state", "once"])

    def start_docker(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.PREPARE_RUNTIME_DATA,
            GuestBootstrapStep.START_DOCKER,
        )
        self.systemctl("enable", "--now", "docker")

    def start_avahi(self) -> None:
        self.operations.run(["hostnamectl", "set-hostname", "tirosh-vitalserver"])
        self.systemctl("enable", "--now", "avahi-daemon")

    def start_guest_background_services(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.START_DOCKER,
            GuestBootstrapStep.START_GUEST_BACKGROUND_SERVICES,
        )
        self.systemctl("start", RuntimeService.REDIS_BACKUP_TIMER.value)
        self.systemctl("start", RuntimeService.COMMAND_POLLER.value)
        self.systemctl("start", "tirosh-guest-observability.service")

    def prepare_shared_directories(self) -> None:
        self.context.vital_files_mount.mkdir(parents=True, exist_ok=True)
        (self.context.runtime_dir.parent / "vr-release").mkdir(
            parents=True,
            exist_ok=True,
        )

    def load_bundled_docker_images(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.START_DOCKER,
            GuestBootstrapStep.LOAD_DOCKER_IMAGES,
        )
        image_dir = self.context.deploy_dir / "docker-images"
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
            self.operations.run(["docker", "load", "-i", str(image_bundle)])
            loaded = True
        if loaded:
            print("Bundled Docker images are loaded.")

    def run_docker_runtime_smoke(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.LOAD_DOCKER_IMAGES,
            GuestBootstrapStep.RUN_DOCKER_SMOKE,
        )
        completed = self.operations.run(
            ["docker", "image", "inspect", self.context.docker_smoke_image],
            check=False,
        )
        if completed.returncode != 0:
            self.write_bootstrap_result(
                "failed",
                "Guest Docker runtime smoke image is missing.",
                ("guest-bootstrap-docker-runtime-failed",),
            )
            raise RuntimeError("Guest Docker runtime smoke image is missing.")
        smoke = self.operations.run(
            [
                "docker",
                "run",
                "--rm",
                "--network",
                "none",
                "--security-opt",
                "seccomp=unconfined",
                self.context.docker_smoke_image,
                "true",
            ],
            check=False,
        )
        if smoke.returncode == 0:
            print(
                "Docker runtime smoke passed using "
                f"{self.context.docker_smoke_image}."
            )
            return
        self.write_bootstrap_result(
            "failed",
            "Guest Docker runtime smoke failed.",
            ("guest-bootstrap-docker-runtime-failed",),
        )
        raise RuntimeError("Guest Docker runtime smoke failed.")

    def cleanup_docker_cache(self) -> None:
        self.operations.run(["docker", "image", "prune", "-f"], check=False)

    def build_missing_images(self) -> None:
        for image, service in (
            ("vitalserver:2.3.4", "app"),
            ("vitalserver-audit-proxy:0.1.0", "audit-proxy"),
        ):
            completed = self.operations.run(
                ["docker", "image", "inspect", image],
                check=False,
            )
            if completed.returncode != 0:
                self.operations.run(compose_command(["build", service]))

    def start_compose(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.RUN_DOCKER_SMOKE,
            GuestBootstrapStep.START_COMPOSE,
        )
        self.systemctl("start", RuntimeService.COMPOSE.value)

    def start_container_logs(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.START_COMPOSE,
            GuestBootstrapStep.START_CONTAINER_LOGS,
        )
        self.systemctl("start", RuntimeService.CONTAINER_LOGS.value)

    def wait_for_vitalserver_edge(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.START_COMPOSE,
            GuestBootstrapStep.WAIT_EDGE_READY,
        )
        print(f"Waiting for VitalServer edge readiness: {self.context.edge_ready_url}")
        deadline = time.time() + self.context.edge_ready_timeout_seconds
        while time.time() < deadline:
            status = self.operations.http_status(
                self.context.edge_ready_url,
                self.context.edge_ready_http_timeout_seconds,
            )
            if 200 <= status < 300:
                print(f"VitalServer edge is ready: {status}")
                self.operations.run(["/usr/local/bin/tirosh-runtime-state", "once"])
                return
            self.operations.sleep(self.context.edge_ready_poll_seconds)
        self.operations.run(compose_command(["ps"]), check=False)
        self.operations.run(compose_command(["logs", "--tail=200"]), check=False)
        self.operations.run(["df", "-h", "/"], check=False)
        raise RuntimeError("VitalServer edge did not become ready")

    def restart_runtime_state(self) -> None:
        self.systemctl("restart", RuntimeService.RUNTIME_STATE.value)

    def start_optional_testkit(self) -> None:
        self.operations.run(
            ["/usr/local/bin/tirosh-vitalserver-compose", "testkit-up-logged"]
        )

    def run_runtime_boot_smoke_if_requested(self) -> None:
        if runtime_boot_smoke_enabled(self.context.deploy_dir):
            self.operations.run(["/usr/local/bin/tirosh-vitalserver-runtime-boot-smoke"])

    def systemctl(
        self,
        *arguments: str,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return self.operations.run(["systemctl", *arguments], check=check)

    def command_text(self, arguments: list[str]) -> str:
        output = self.operations.output(arguments).strip().splitlines()
        if not output:
            raise RuntimeError("command returned no output: " + " ".join(arguments))
        return output[0].strip()


def runtime_package_missing_commands(operations: GuestBootstrapOperations) -> list[str]:
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
        if operations.run(command, check=False).returncode != 0:
            missing.append(name)
    with tempfile.TemporaryDirectory(prefix="tirosh-venv-check-") as temporary_dir:
        test_venv = Path(temporary_dir) / "venv"
        venv = operations.run(
            ["python3", "-m", "venv", str(test_venv)],
            check=False,
        )
    if venv.returncode != 0:
        missing.append("python3-venv/ensurepip")
    return missing


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


def parent_device_from_source(root_source: str, partition_number: str) -> str:
    if root_source.startswith("/dev/nvme") or root_source.startswith("/dev/mmcblk"):
        return root_source.removeprefix("/dev/").removesuffix(f"p{partition_number}")
    return root_source.removeprefix("/dev/").removesuffix(partition_number)


def partition_number_from_source(root_source: str) -> str:
    if root_source.startswith("/dev/nvme") or root_source.startswith("/dev/mmcblk"):
        return root_source.rsplit("p", 1)[-1]
    match = re.search(r"(\d+)$", root_source)
    return match.group(1) if match else ""


def run_command(
    arguments: list[str],
    *,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, check=check, text=True)


def command_output(arguments: list[str]) -> str:
    return subprocess.run(
        arguments,
        check=False,
        capture_output=True,
        text=True,
    ).stdout


def read_boot_id() -> str:
    boot_id = Path("/proc/sys/kernel/random/boot_id").read_text(
        encoding="utf-8"
    ).strip()
    if not boot_id:
        raise RuntimeError("guest boot id is empty")
    return boot_id


def http_status(url: str, timeout_seconds: float) -> int:
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
        return 0
    try:
        return int(completed.stdout.strip())
    except ValueError:
        return 0
