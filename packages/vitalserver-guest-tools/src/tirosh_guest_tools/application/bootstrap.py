from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path

from tirosh_guest_tools.contracts import RuntimeFileName

DOCKER_SMOKE_IMAGE = "redis:3.2.12-alpine"
EDGE_READY_URL = "http://127.0.0.1/ready"
EDGE_READY_TIMEOUT_SECONDS = 600.0
EDGE_READY_POLL_SECONDS = 3.0
EDGE_READY_HTTP_TIMEOUT_SECONDS = 5.0


class GuestBootstrapStep(StrEnum):
    MOUNT_SHARES = "mount-shares"
    SYNC_CLOCK = "sync-clock"
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
    RUN_RUNTIME_BOOT_SMOKE = "run-runtime-boot-smoke"


@dataclass(frozen=True)
class GuestBootstrapContext:
    deploy_dir: Path
    runtime_dir: Path
    vital_files_mount: Path
    bootstrap_result: Path
    docker_smoke_image: str = DOCKER_SMOKE_IMAGE
    edge_ready_url: str = EDGE_READY_URL
    edge_ready_timeout_seconds: float = EDGE_READY_TIMEOUT_SECONDS
    edge_ready_poll_seconds: float = EDGE_READY_POLL_SECONDS
    edge_ready_http_timeout_seconds: float = EDGE_READY_HTTP_TIMEOUT_SECONDS


@dataclass(frozen=True)
class BootstrapResultDocument:
    boot_id: str
    message: str
    operation: str
    reason_codes: tuple[str, ...]
    schema_version: int
    status: str
    updated_at: str

    @classmethod
    def create(
        cls,
        *,
        boot_id: str,
        message: str,
        reason_codes: tuple[str, ...],
        status: str,
        updated_at: str,
    ) -> BootstrapResultDocument:
        return cls(
            boot_id=boot_id,
            message=message,
            operation="bootstrap",
            reason_codes=reason_codes,
            schema_version=3,
            status=status,
            updated_at=updated_at,
        )


@dataclass(frozen=True)
class EdgeReadinessProbeResult:
    status_code: int | None
    failure: str | None = None

    @property
    def ready(self) -> bool:
        return self.status_code is not None and 200 <= self.status_code < 300


@dataclass(frozen=True)
class DockerSmokeResult:
    passed: bool
    missing_image: bool = False


@dataclass(frozen=True)
class GuestBootstrapOperations:
    current_time_seconds: Callable[[], float]
    sleep: Callable[[float], None]
    now: Callable[[], str]
    boot_id: Callable[[], str]
    mount_shares: Callable[[], None]
    sync_clock: Callable[[GuestBootstrapContext], None]
    write_bootstrap_result: Callable[[Path, BootstrapResultDocument], None]
    missing_deploy_bundle_files: Callable[[GuestBootstrapContext], list[Path]]
    expand_root_filesystem: Callable[[], None]
    missing_runtime_packages: Callable[[], list[str]]
    install_runtime_files: Callable[[GuestBootstrapContext], None]
    prepare_runtime_data: Callable[[], None]
    write_initial_runtime_state: Callable[[], None]
    start_docker: Callable[[], None]
    start_avahi: Callable[[], None]
    start_guest_background_services: Callable[[], None]
    prepare_shared_directories: Callable[[GuestBootstrapContext], None]
    load_bundled_docker_images: Callable[[GuestBootstrapContext], None]
    run_docker_runtime_smoke: Callable[[str], DockerSmokeResult]
    cleanup_docker_cache: Callable[[], None]
    build_missing_images: Callable[[], None]
    start_compose: Callable[[], None]
    start_container_logs: Callable[[], None]
    probe_edge_readiness: Callable[[str, float], EdgeReadinessProbeResult]
    write_runtime_state_once: Callable[[], None]
    write_edge_diagnostics: Callable[[], None]
    restart_runtime_state: Callable[[], None]
    runtime_boot_smoke_enabled: Callable[[Path], bool]
    run_runtime_boot_smoke: Callable[[], None]


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


def run_guest_bootstrap(
    *,
    context: GuestBootstrapContext,
    operations: GuestBootstrapOperations,
) -> None:
    workflow = GuestBootstrapWorkflow(context=context, operations=operations)
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
            (GuestBootstrapStep.MOUNT_SHARES, self.operations.mount_shares),
            (GuestBootstrapStep.SYNC_CLOCK, self.sync_clock),
            (GuestBootstrapStep.WRITE_RUNNING_RESULT, self.write_running_result),
            (GuestBootstrapStep.VALIDATE_DEPLOY_CONTRACT, self.require_deploy_bundle),
            (
                GuestBootstrapStep.EXPAND_ROOT_FILESYSTEM,
                self.operations.expand_root_filesystem,
            ),
            (
                GuestBootstrapStep.REQUIRE_RUNTIME_PACKAGES,
                self.require_runtime_packages,
            ),
            (GuestBootstrapStep.INSTALL_RUNTIME_FILES, self.install_runtime_files),
            (GuestBootstrapStep.PREPARE_RUNTIME_DATA, self.prepare_runtime_data),
            (
                GuestBootstrapStep.WRITE_INITIAL_RUNTIME_STATE,
                self.operations.write_initial_runtime_state,
            ),
            (GuestBootstrapStep.START_DOCKER, self.start_docker),
            (GuestBootstrapStep.START_AVAHI, self.operations.start_avahi),
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
            (
                GuestBootstrapStep.CLEANUP_DOCKER_CACHE,
                self.operations.cleanup_docker_cache,
            ),
            (
                GuestBootstrapStep.BUILD_MISSING_IMAGES,
                self.operations.build_missing_images,
            ),
            (GuestBootstrapStep.START_COMPOSE, self.start_compose),
            (GuestBootstrapStep.START_CONTAINER_LOGS, self.start_container_logs),
            (GuestBootstrapStep.WAIT_EDGE_READY, self.wait_for_vitalserver_edge),
            (
                GuestBootstrapStep.RESTART_RUNTIME_STATE,
                self.operations.restart_runtime_state,
            ),
            (GuestBootstrapStep.WRITE_COMPLETED_RESULT, self.write_completed_result),
            (
                GuestBootstrapStep.RUN_RUNTIME_BOOT_SMOKE,
                self.run_runtime_boot_smoke_if_requested,
            ),
        ]

    def execute(self, step: GuestBootstrapStep, action: Callable[[], None]) -> None:
        action()
        self.state.complete(step)

    def write_running_result(self) -> None:
        self.write_bootstrap_result("running", "Guest bootstrap is running.", ())

    def sync_clock(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.MOUNT_SHARES,
            GuestBootstrapStep.SYNC_CLOCK,
        )
        self.operations.sync_clock(self.context)

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
        document = BootstrapResultDocument.create(
            boot_id=self.operations.boot_id(),
            message=message,
            reason_codes=reason_codes,
            status=status,
            updated_at=self.operations.now(),
        )
        self.operations.write_bootstrap_result(self.context.bootstrap_result, document)
        if status in {"completed", "failed"}:
            self.state.result_terminal = True

    def require_deploy_bundle(self) -> None:
        missing = self.operations.missing_deploy_bundle_files(self.context)
        if missing:
            raise RuntimeError(
                "missing deploy bundle files: "
                + ", ".join(str(path) for path in missing)
            )

    def require_runtime_packages(self) -> None:
        missing = self.operations.missing_runtime_packages()
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
        self.operations.install_runtime_files(self.context)

    def prepare_runtime_data(self) -> None:
        self.operations.prepare_runtime_data()

    def start_docker(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.PREPARE_RUNTIME_DATA,
            GuestBootstrapStep.START_DOCKER,
        )
        self.operations.start_docker()

    def start_guest_background_services(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.START_DOCKER,
            GuestBootstrapStep.START_GUEST_BACKGROUND_SERVICES,
        )
        self.operations.start_guest_background_services()

    def prepare_shared_directories(self) -> None:
        self.operations.prepare_shared_directories(self.context)

    def load_bundled_docker_images(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.START_DOCKER,
            GuestBootstrapStep.LOAD_DOCKER_IMAGES,
        )
        self.operations.load_bundled_docker_images(self.context)

    def run_docker_runtime_smoke(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.LOAD_DOCKER_IMAGES,
            GuestBootstrapStep.RUN_DOCKER_SMOKE,
        )
        result = self.operations.run_docker_runtime_smoke(
            self.context.docker_smoke_image
        )
        if result.passed:
            print(
                "Docker runtime smoke passed using "
                f"{self.context.docker_smoke_image}."
            )
            return
        if result.missing_image:
            self.write_bootstrap_result(
                "failed",
                "Guest Docker runtime smoke image is missing.",
                ("guest-bootstrap-docker-runtime-failed",),
            )
            raise RuntimeError("Guest Docker runtime smoke image is missing.")
        self.write_bootstrap_result(
            "failed",
            "Guest Docker runtime smoke failed.",
            ("guest-bootstrap-docker-runtime-failed",),
        )
        raise RuntimeError("Guest Docker runtime smoke failed.")

    def start_compose(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.RUN_DOCKER_SMOKE,
            GuestBootstrapStep.START_COMPOSE,
        )
        self.operations.start_compose()

    def start_container_logs(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.START_COMPOSE,
            GuestBootstrapStep.START_CONTAINER_LOGS,
        )
        self.operations.start_container_logs()

    def wait_for_vitalserver_edge(self) -> None:
        self.state.require_completed(
            GuestBootstrapStep.START_COMPOSE,
            GuestBootstrapStep.WAIT_EDGE_READY,
        )
        print(f"Waiting for VitalServer edge readiness: {self.context.edge_ready_url}")
        deadline = (
            self.operations.current_time_seconds()
            + self.context.edge_ready_timeout_seconds
        )
        last_failure: str | None = None
        while self.operations.current_time_seconds() < deadline:
            result = self.operations.probe_edge_readiness(
                self.context.edge_ready_url,
                self.context.edge_ready_http_timeout_seconds,
            )
            if result.ready:
                print(f"VitalServer edge is ready: {result.status_code}")
                self.operations.write_runtime_state_once()
                return
            last_failure = result.failure
            self.operations.sleep(self.context.edge_ready_poll_seconds)
        self.operations.write_edge_diagnostics()
        if last_failure:
            raise RuntimeError(
                "VitalServer edge did not become ready: " + last_failure
            )
        raise RuntimeError("VitalServer edge did not become ready")

    def run_runtime_boot_smoke_if_requested(self) -> None:
        if self.operations.runtime_boot_smoke_enabled(self.context.deploy_dir):
            self.operations.run_runtime_boot_smoke()


def expected_deploy_bundle_files(context: GuestBootstrapContext) -> tuple[Path, ...]:
    return (
        context.deploy_dir / RuntimeFileName.COMPOSE.value,
        context.deploy_dir / RuntimeFileName.RUNTIME_CONFIG.value,
    )
