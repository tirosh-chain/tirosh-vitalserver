from __future__ import annotations

import json
import subprocess
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote

from tirosh_guest_tools.application.runtime_boot_smoke_manifest import (
    RUNTIME_BOOT_SMOKE_MANIFEST,
    RuntimeBootSmokeContext,
    RuntimeBootSmokeOperations,
    RuntimeBootSmokeRun,
    RuntimeBootSmokeStage,
)
from tirosh_guest_tools.application.runtime_data_prepare import (
    read_runtime_data_contract,
)
from tirosh_guest_tools.contracts import (
    ComposeService,
    RootfsSmokeStatus,
    RuntimeConfigKey,
    RuntimeFileName,
    RuntimeService,
)
from tirosh_guest_tools.infrastructure.common import (
    DEPLOY_DIR,
    RUNTIME_DIR,
    mount_runtime_share,
    read_json,
    utc_now,
    write_json,
)

BOOTSTRAP_RESULT_SCHEMA_VERSION = 3
RUNTIME_STATE_SCHEMA_VERSION = 1
MAX_RUNTIME_STATE_AGE_SECONDS = 180
COMPOSE_READY_TIMEOUT_SECONDS = 120.0
COMPOSE_READY_POLL_SECONDS = 2.0
HTTP_TIMEOUT_SECONDS = 5.0
GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS = 60.0
SYSTEMD_TIMEOUT_SECONDS = 10.0
GUEST_CONTROL_API_BASE_URL = "http://127.0.0.1:18330"
LAB_REPLAY_SMOKE_VITAL_FILE = "/mnt/tirosh-vital-files/runtime-boot-smoke-replay.vital"

REQUIRED_SYSTEMD_UNITS = (
    "docker.service",
    RuntimeService.RUNTIME_STATE.value,
    RuntimeService.COMPOSE.value,
    "tirosh-guest-observability.service",
    RuntimeService.GUEST_CONTROL_API.value,
)

REQUIRED_GUEST_CONTROL_CAPABILITIES = (
    "services:list",
    "services:status",
    "services:start",
    "services:stop",
    "services:restart",
    "stack:reconcile",
    "lab:scenarios",
    "lab:sessions:create",
    "lab:sessions:get",
    "lab:sessions:start",
    "lab:sessions:stop",
    "lab:vital-files:replay",
    "recorder-ingress:status:get",
    "operations:get",
    "maintenance:redis-backup:create",
    "maintenance:redis-restore:create",
    "maintenance:datastore-repair:create",
    "maintenance:update-activation:create",
    "maintenance:update-shutdown:create",
)

BASE_REQUIRED_COMPOSE_SERVICES = (
    ComposeService.POSTGRES.value,
    ComposeService.REDIS.value,
    ComposeService.APP.value,
    ComposeService.RECORDER_INGRESS.value,
    ComposeService.VITALDB_OBSERVER.value,
    ComposeService.REDIS_RELAY.value,
    ComposeService.LAB.value,
    ComposeService.REDIS_UI.value,
    ComposeService.SWAGGER_UI.value,
    ComposeService.EDGE.value,
)


@dataclass(frozen=True)
class ComposeServiceRequirement:
    name: str
    require_healthy: bool = True


class RuntimeBootSmokeStageFailed(RuntimeError):
    pass


def default_context() -> RuntimeBootSmokeContext:
    read_required_json_object(
        DEPLOY_DIR / RuntimeFileName.RUNTIME_CONFIG.value,
        "runtime config",
    )
    metadata = read_required_json_object(
        DEPLOY_DIR / "build-metadata/rootfs-input.json",
        "runtime boot smoke metadata",
    )
    smoke_metadata = metadata.get("runtimeBootSmoke")
    if not isinstance(smoke_metadata, dict):
        raise RuntimeError("runtime boot smoke metadata is missing runtimeBootSmoke")
    if smoke_metadata.get("enabled") is not True:
        raise RuntimeError("runtime boot smoke is not explicitly enabled")
    run_id = require_non_empty_string(
        smoke_metadata.get("runId"),
        "runtime boot smoke runId",
    )
    return RuntimeBootSmokeContext(
        runtime_dir=RUNTIME_DIR,
        deploy_dir=DEPLOY_DIR,
        manifest_path=RUNTIME_DIR / RUNTIME_BOOT_SMOKE_MANIFEST,
        run_id=run_id,
        max_runtime_state_age_seconds=MAX_RUNTIME_STATE_AGE_SECONDS,
        compose_ready_timeout_seconds=COMPOSE_READY_TIMEOUT_SECONDS,
        dev_build=False,
    )


def default_operations() -> RuntimeBootSmokeOperations:
    return RuntimeBootSmokeOperations(
        mount_runtime_share=mount_runtime_share,
        read_json=read_json,
        write_json=write_json,
        run=run_command,
        http_status=http_status,
        http_json=http_json,
        now=lambda: datetime.now(UTC),
        sleep=time.sleep,
    )


def run_runtime_boot_smoke(
    *,
    context: RuntimeBootSmokeContext | None = None,
    operations: RuntimeBootSmokeOperations | None = None,
) -> None:
    operations = operations or default_operations()
    operations.mount_runtime_share()
    context = context or default_context()
    context.runtime_dir.mkdir(parents=True, exist_ok=True)
    run = RuntimeBootSmokeRun(context=context, operations=operations)
    run.write_manifest()

    try:
        bootstrap_result = execute_stage(
            run,
            "bootstrap-result",
            lambda active_run: validate_bootstrap_result(active_run),
        )
        execute_stage(
            run,
            "runtime-state",
            lambda active_run: validate_runtime_state(active_run, bootstrap_result),
        )
        execute_stage(
            run,
            "systemd-units",
            validate_systemd_units,
        )
        execute_stage(
            run,
            "runtime-data",
            validate_runtime_data,
        )
        execute_stage(
            run,
            "http",
            validate_http,
        )
        execute_stage(
            run,
            "compose-services",
            lambda active_run: validate_compose_services(
                active_run,
                bootstrap_result,
            ),
        )
        execute_stage(
            run,
            "guest-control-api",
            validate_guest_control_api,
        )
        execute_stage(
            run,
            "disk-health",
            lambda active_run: validate_disk_health(active_run, bootstrap_result),
        )
        execute_stage(
            run,
            "capabilities",
            validate_capabilities,
        )
        execute_stage(
            run,
            "runtime-share",
            validate_runtime_share,
        )
        execute_stage(
            run,
            "feature-readiness",
            lambda active_run: validate_feature_readiness(active_run, bootstrap_result),
        )
    except RuntimeBootSmokeStageFailed:
        run.write_manifest()
        raise SystemExit(1) from None

    run.write_manifest()


def execute_stage(
    run: RuntimeBootSmokeRun,
    name: str,
    action: Callable[[RuntimeBootSmokeRun], tuple[str, dict[str, Any]]],
) -> dict[str, Any]:
    started_at = utc_now()
    run.stages.append(
        RuntimeBootSmokeStage(
            name=name,
            status=RootfsSmokeStatus.RUNNING,
            started_at=started_at,
            completed_at="",
            message="stage is running",
        )
    )
    run.write_manifest()
    try:
        message, details = action(run)
    except Exception as error:
        run.stages[-1] = RuntimeBootSmokeStage(
            name=name,
            status=RootfsSmokeStatus.FAILED,
            started_at=started_at,
            completed_at=utc_now(),
            message=str(error),
        )
        run.write_manifest()
        raise RuntimeBootSmokeStageFailed(name) from error

    run.stages[-1] = RuntimeBootSmokeStage(
        name=name,
        status=RootfsSmokeStatus.PASSED,
        started_at=started_at,
        completed_at=utc_now(),
        message=message,
        details=details,
    )
    run.write_manifest()
    return details


def validate_bootstrap_result(
    run: RuntimeBootSmokeRun,
) -> tuple[str, dict[str, Any]]:
    path = run.context.runtime_dir / RuntimeFileName.BOOTSTRAP_RESULT.value
    document = run.operations.read_json(path)
    require_equal(
        document.get("schemaVersion"),
        BOOTSTRAP_RESULT_SCHEMA_VERSION,
        f"bootstrap result schema mismatch: {path}",
    )
    status = document.get("status")
    if status != "completed":
        raise RuntimeError(
            f"bootstrap result is not completed: status={status} "
            f"reasonCodes={document.get('reasonCodes')}"
        )
    boot_id = require_non_empty_string(document.get("bootID"), "bootstrap bootID")
    updated_at = require_non_empty_string(
        document.get("updatedAt"),
        "bootstrap updatedAt",
    )
    return (
        "bootstrap result completed",
        {
            "path": str(path),
            "bootID": boot_id,
            "updatedAt": updated_at,
            "reasonCodes": list_value(document.get("reasonCodes")),
        },
    )


def validate_runtime_state(
    run: RuntimeBootSmokeRun,
    bootstrap_result: dict[str, Any],
) -> tuple[str, dict[str, Any]]:
    path = run.context.runtime_dir / RuntimeFileName.RUNTIME_STATE.value
    document = run.operations.read_json(path)
    require_equal(
        document.get("schemaVersion"),
        RUNTIME_STATE_SCHEMA_VERSION,
        f"runtime state schema mismatch: {path}",
    )
    boot_id = require_non_empty_string(document.get("bootID"), "runtime state bootID")
    bootstrap_boot_id = bootstrap_result.get("bootID")
    if bootstrap_boot_id and boot_id != bootstrap_boot_id:
        raise RuntimeError(
            "runtime state bootID does not match bootstrap result: "
            f"runtime={boot_id} bootstrap={bootstrap_boot_id}"
        )
    vm_ip = require_non_empty_string(document.get("vmIP"), "runtime state vmIP")
    if vm_ip.startswith(("127.", "169.254.")):
        raise RuntimeError(f"runtime state vmIP is not routable: {vm_ip}")
    updated_at = require_non_empty_string(
        document.get("updatedAt"),
        "runtime state updatedAt",
    )
    age_seconds = document_age_seconds(updated_at, run.operations.now())
    if age_seconds > run.context.max_runtime_state_age_seconds:
        raise RuntimeError(
            "runtime state is stale: "
            f"ageSeconds={age_seconds:.1f} "
            f"maxSeconds={run.context.max_runtime_state_age_seconds}"
        )
    probe_errors = document.get("probeErrors")
    if not isinstance(probe_errors, list):
        raise RuntimeError("runtime state probeErrors must be an explicit list")
    if probe_errors:
        raise RuntimeError(f"runtime state contains probe errors: {probe_errors}")
    return (
        "runtime state is valid and fresh",
        {
            "path": str(path),
            "bootID": boot_id,
            "vmIP": vm_ip,
            "updatedAt": updated_at,
            "ageSeconds": round(age_seconds, 1),
            "document": document,
        },
    )


def validate_systemd_units(run: RuntimeBootSmokeRun) -> tuple[str, dict[str, Any]]:
    units: list[dict[str, Any]] = []
    for service in REQUIRED_SYSTEMD_UNITS:
        active_state = systemd_active_state(run, service)
        units.append({"service": service, "activeState": active_state})
        if active_state != "active":
            raise RuntimeError(
                f"required systemd unit is not active: "
                f"service={service} activeState={active_state}"
            )
    return "required systemd units are active", {"units": units}


def validate_http(run: RuntimeBootSmokeRun) -> tuple[str, dict[str, Any]]:
    endpoints = []
    for name, url in (
        ("ready", "http://127.0.0.1/ready"),
        ("health", "http://127.0.0.1/health"),
    ):
        status = run.operations.http_status(url, HTTP_TIMEOUT_SECONDS)
        endpoints.append({"name": name, "url": url, "status": status})
        if not 200 <= status < 300:
            raise RuntimeError(f"runtime HTTP endpoint is not ready: {url} {status}")
    return "runtime HTTP endpoints are ready", {"endpoints": endpoints}


def validate_guest_control_api(
    run: RuntimeBootSmokeRun,
) -> tuple[str, dict[str, Any]]:
    ready = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/ready",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    require_equal(ready.get("status"), "ready", "guest control API is not ready")

    capabilities = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/capabilities",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    capability_values = list_value(capabilities.get("capabilities"))
    require_guest_control_capabilities(capability_values)

    services = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/services",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    service_values = list_value(services.get("services"))
    for service in (ComposeService.POSTGRES.value, ComposeService.APP.value):
        if service not in service_values:
            raise RuntimeError(f"guest control API service is missing: {service}")

    app_status = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/services/{ComposeService.APP.value}/status",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    require_equal(
        app_status.get("service"),
        ComposeService.APP.value,
        "guest control API app status service mismatch",
    )
    require_non_empty_string(app_status.get("state"), "guest control API app state")

    recorder_ingress_status = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/recorder-ingress/status",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    require_equal(
        recorder_ingress_status.get("readState"),
        "loaded",
        "guest control API recorder-ingress status read is not loaded",
    )
    require_equal(
        recorder_ingress_status.get("readError"),
        None,
        "guest control API recorder-ingress status read has an error",
    )
    recorder_ingress_document = recorder_ingress_status.get("document")
    if not isinstance(recorder_ingress_document, dict):
        raise RuntimeError(
            "guest control API recorder-ingress status document is invalid"
        )
    require_non_empty_string(
        recorder_ingress_document.get("startedAt"),
        "guest control API recorder-ingress startedAt",
    )

    restart = run.operations.http_json(
        "POST",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/services/{ComposeService.APP.value}/restart",
        GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS,
        None,
    )
    operation_id = require_non_empty_string(
        restart.get("operationId"),
        "guest control API restart operationId",
    )
    require_equal(
        restart.get("state"),
        "completed",
        "guest control API restart operation did not complete",
    )

    operation = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/operations/{operation_id}",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    require_equal(
        operation.get("operationId"),
        operation_id,
        "guest control API operation read returned the wrong operation",
    )
    require_equal(
        operation.get("state"),
        "completed",
        "guest control API persisted operation is not completed",
    )

    reconcile = run.operations.http_json(
        "POST",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/stack/reconcile",
        GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS,
        None,
    )
    reconcile_operation_id = require_non_empty_string(
        reconcile.get("operationId"),
        "guest control API stack reconcile operationId",
    )
    require_equal(
        reconcile.get("service"),
        "guest-stack",
        "guest control API stack reconcile service mismatch",
    )
    require_equal(
        reconcile.get("command"),
        "reconcile",
        "guest control API stack reconcile command mismatch",
    )
    require_equal(
        reconcile.get("state"),
        "completed",
        "guest control API stack reconcile operation did not complete",
    )

    reconcile_operation = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/operations/{reconcile_operation_id}",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    require_equal(
        reconcile_operation.get("operationId"),
        reconcile_operation_id,
        "guest control API stack reconcile operation read returned the wrong operation",
    )
    require_equal(
        reconcile_operation.get("state"),
        "completed",
        "guest control API persisted stack reconcile operation is not completed",
    )
    lab_scenarios = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/lab/scenarios",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    require_equal(
        lab_scenarios.get("state"),
        "loaded",
        "guest control API Product Lab scenarios are not loaded",
    )
    scenarios = list_value(lab_scenarios.get("scenarios"))
    if not scenarios:
        raise RuntimeError("guest control API Product Lab scenarios are empty")
    first_scenario = scenarios[0]
    if not isinstance(first_scenario, dict):
        raise RuntimeError("guest control API Product Lab scenario is invalid")
    scenario_id = require_non_empty_string(
        first_scenario.get("scenarioId"),
        "guest control API Product Lab scenarioId",
    )
    lab_session_operations = validate_product_lab_session_operations(
        run,
        scenario_id,
    )

    return (
        "guest control API is ready and persists service and Lab operations",
        {
            "ready": ready,
            "capabilities": capability_values,
            "services": service_values,
            "appStatus": app_status,
            "recorderIngressStatus": recorder_ingress_status,
            "operation": operation,
            "reconcileOperation": reconcile_operation,
            "labScenarios": lab_scenarios,
            "labSessionOperations": lab_session_operations,
        },
    )


def validate_product_lab_session_operations(
    run: RuntimeBootSmokeRun,
    scenario_id: str,
) -> dict[str, Any]:
    create = run.operations.http_json(
        "POST",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/lab/sessions",
        GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS,
        {
            "scenarioId": scenario_id,
            "name": "RuntimeBootSmokeLab",
            "recorderCount": 1,
            "targetURL": "http://edge/",
        },
    )
    session_id = validate_lab_session_response(
        create,
        subject="guest control API Product Lab create session",
        expected_state=None,
    )
    create_operation_id = require_non_empty_string(
        create.get("operationId"),
        "guest control API Product Lab create operationId",
    )
    session_path_segment = quote(session_id, safe="")

    read = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/lab/sessions/{session_path_segment}",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    read_session_id = validate_lab_session_response(
        read,
        subject="guest control API Product Lab read session",
        expected_state=None,
    )
    if read_session_id != session_id:
        raise RuntimeError(
            "guest control API Product Lab read returned wrong session: "
            f"expected={session_id} actual={read_session_id}"
        )

    start = run.operations.http_json(
        "POST",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/lab/sessions/{session_path_segment}/start",
        GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS,
        None,
    )
    validate_lab_session_response(
        start,
        subject="guest control API Product Lab start session",
        expected_state="running",
    )
    start_operation_id = require_non_empty_string(
        start.get("operationId"),
        "guest control API Product Lab start operationId",
    )

    stop = run.operations.http_json(
        "POST",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/lab/sessions/{session_path_segment}/stop",
        GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS,
        None,
    )
    validate_lab_session_response(
        stop,
        subject="guest control API Product Lab stop session",
        expected_state="stopped",
    )
    stop_operation_id = require_non_empty_string(
        stop.get("operationId"),
        "guest control API Product Lab stop operationId",
    )
    replay_vital_file_path = prepare_lab_replay_smoke_vital_file(run)
    replay = run.operations.http_json(
        "POST",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/lab/vital-files/replay",
        GUEST_CONTROL_OPERATION_TIMEOUT_SECONDS,
        {
            "vitalFilePath": replay_vital_file_path,
            "sessionName": "RuntimeBootSmokeReplay",
            "targetURL": "http://edge/",
        },
    )
    replay_session_id = validate_lab_session_response(
        replay,
        subject="guest control API Product Lab replay vital file",
        expected_state=None,
    )
    replay_operation_id = require_non_empty_string(
        replay.get("operationId"),
        "guest control API Product Lab replay operationId",
    )

    return {
        "scenarioId": scenario_id,
        "sessionId": session_id,
        "replaySessionId": replay_session_id,
        "create": create,
        "read": read,
        "start": start,
        "stop": stop,
        "replay": replay,
        "operationIds": [
            create_operation_id,
            start_operation_id,
            stop_operation_id,
            replay_operation_id,
        ],
    }


def prepare_lab_replay_smoke_vital_file(run: RuntimeBootSmokeRun) -> str:
    path = LAB_REPLAY_SMOKE_VITAL_FILE
    script = (
        "from pathlib import Path; "
        f"path = Path({path!r}); "
        "path.parent.mkdir(parents=True, exist_ok=True); "
        "path.write_bytes(b'runtime boot smoke vital replay placeholder\\n')"
    )
    completed = run.operations.run(
        ["python3", "-c", script],
        check=False,
        capture_output=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            "failed to prepare Product Lab replay .vital smoke file: "
            f"exitCode={completed.returncode} stdout={completed.stdout!r} "
            f"stderr={completed.stderr!r}"
        )
    return path


def validate_lab_session_response(
    document: dict[str, Any],
    *,
    subject: str,
    expected_state: str | None,
) -> str:
    require_equal(
        document.get("state"),
        "loaded",
        f"{subject} response is not loaded",
    )
    session = document.get("session")
    if not isinstance(session, dict):
        raise RuntimeError(f"{subject} response is missing session")
    session_id = require_non_empty_string(
        session.get("sessionId"),
        f"{subject} sessionId",
    )
    if expected_state is not None:
        require_equal(
            session.get("state"),
            expected_state,
            f"{subject} state mismatch",
        )
    return session_id


def validate_runtime_data(run: RuntimeBootSmokeRun) -> tuple[str, dict[str, Any]]:
    contract = read_runtime_data_contract(run.context.deploy_dir)
    completed = run.operations.run(
        ["findmnt", "--json", "--mountpoint", contract.mount_path],
        check=False,
        capture_output=True,
        timeout_seconds=SYSTEMD_TIMEOUT_SECONDS,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        raise RuntimeError(
            "runtime data disk is not mounted: "
            f"mountPath={contract.mount_path}"
        )
    try:
        mount_document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"findmnt returned invalid JSON: {error}") from error
    filesystems = mount_document.get("filesystems")
    if not isinstance(filesystems, list) or not filesystems:
        raise RuntimeError(
            "runtime data mount proof is missing filesystems: "
            f"mountPath={contract.mount_path}"
        )
    mount = filesystems[0]
    if not isinstance(mount, dict):
        raise RuntimeError("runtime data mount proof is invalid")
    if mount.get("target") != contract.mount_path:
        raise RuntimeError(
            "runtime data mount target mismatch: "
            f"expected={contract.mount_path} actual={mount.get('target')}"
        )
    if mount.get("fstype") not in ("ext4", "ext3", "ext2"):
        raise RuntimeError(
            "runtime data filesystem type is unsupported: "
            f"mountPath={contract.mount_path} fstype={mount.get('fstype')}"
        )
    docker_root_completed = run.operations.run(
        ["docker", "info", "--format", "{{json .DockerRootDir}}"],
        check=False,
        capture_output=True,
        timeout_seconds=SYSTEMD_TIMEOUT_SECONDS,
    )
    if docker_root_completed.returncode != 0:
        reason = (
            docker_root_completed.stderr.strip()
            or str(docker_root_completed.returncode)
        )
        raise RuntimeError(
            f"failed to read Docker root dir: {reason}"
        )
    try:
        docker_root = json.loads(docker_root_completed.stdout.strip())
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"docker info returned invalid DockerRootDir JSON: {error}"
        ) from error
    if docker_root != contract.docker_data_root:
        raise RuntimeError(
            "Docker data-root does not match runtime data contract: "
            f"expected={contract.docker_data_root} actual={docker_root}"
        )
    return (
        "runtime data disk is mounted and used by Docker",
        {
            "mountPath": contract.mount_path,
            "dockerDataRoot": docker_root,
            "containerdRoot": contract.containerd_root,
            "source": mount.get("source"),
            "fstype": mount.get("fstype"),
        },
    )


def validate_compose_services(
    run: RuntimeBootSmokeRun,
    bootstrap_result: dict[str, Any],
) -> tuple[str, dict[str, Any]]:
    del bootstrap_result
    expected = expected_compose_service_requirements(run.context.dev_build)
    deadline = time.monotonic() + run.context.compose_ready_timeout_seconds
    while True:
        stack_status = read_guest_control_stack_status(run)
        observed = observed_stack_services(stack_status)
        missing = missing_compose_services(expected, observed)
        if missing:
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    f"guest control stack status is missing services: {missing}"
                )
            run.operations.sleep(COMPOSE_READY_POLL_SECONDS)
            continue
        unhealthy = unhealthy_compose_services(expected, observed)
        if not unhealthy:
            return (
                "required compose services are ready",
                {
                    "source": "guest-control-api",
                    "stackStatus": stack_status,
                    "services": observed,
                },
            )
        if time.monotonic() >= deadline:
            raise RuntimeError(f"compose services are not ready: {unhealthy}")
        run.operations.sleep(COMPOSE_READY_POLL_SECONDS)


def validate_disk_health(
    run: RuntimeBootSmokeRun,
    bootstrap_result: dict[str, Any],
) -> tuple[str, dict[str, Any]]:
    document = read_current_runtime_state_document(run, bootstrap_result)
    disk_health = document.get("diskHealth")
    if not isinstance(disk_health, dict):
        raise RuntimeError("runtime state diskHealth is missing")
    if disk_health.get("rootFilesystemReadOnly") is not False:
        raise RuntimeError(
            "root filesystem is not explicitly writable: "
            f"{disk_health.get('rootFilesystemReadOnly')}"
        )
    kernel_errors = disk_health.get("kernelErrors")
    if kernel_errors not in ([], None):
        raise RuntimeError(f"kernel disk errors reported: {kernel_errors}")
    return "disk health is clean", {"diskHealth": disk_health}


def validate_capabilities(run: RuntimeBootSmokeRun) -> tuple[str, dict[str, Any]]:
    document = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/capabilities",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    capabilities = list_value(document.get("capabilities"))
    require_guest_control_capabilities(capabilities)
    return (
        "guest control capabilities are available",
        {"source": "guest-control-api", "capabilities": capabilities},
    )


def require_guest_control_capabilities(capabilities: list[Any]) -> None:
    for capability in REQUIRED_GUEST_CONTROL_CAPABILITIES:
        if capability not in capabilities:
            raise RuntimeError(
                f"guest control API capability is missing: {capability}"
            )


def validate_runtime_share(
    run: RuntimeBootSmokeRun,
) -> tuple[str, dict[str, Any]]:
    write_probe = run.context.runtime_dir / ".runtime-boot-smoke-write-check"
    write_probe.write_text(run.context.run_id, encoding="utf-8")
    if write_probe.read_text(encoding="utf-8") != run.context.run_id:
        raise RuntimeError("runtime directory write probe could not be verified")
    write_probe.unlink()
    return (
        "runtime share is writable",
        {"writeProbe": str(write_probe)},
    )


def validate_feature_readiness(
    run: RuntimeBootSmokeRun,
    bootstrap_result: dict[str, Any],
) -> tuple[str, dict[str, Any]]:
    document = read_current_runtime_state_document(run, bootstrap_result)
    runtime_config = run.operations.read_json(
        run.context.deploy_dir / RuntimeFileName.RUNTIME_CONFIG.value
    )
    required_config_keys = [
        RuntimeConfigKey.PUBLIC_HOST.value,
        RuntimeConfigKey.PUBLIC_PORT.value,
        RuntimeConfigKey.VITAL_FILES_DIRECTORY.value,
    ]
    missing_config = [key for key in required_config_keys if key not in runtime_config]
    if missing_config:
        raise RuntimeError(f"runtime config is missing keys: {missing_config}")
    http_probes = document.get("httpProbes")
    if not isinstance(http_probes, dict):
        raise RuntimeError("runtime state httpProbes is missing")
    missing_http_probes = [
        name
        for name in ("guestHTTP", "redisUIHTTP", "swaggerUIHTTP")
        if name not in http_probes
    ]
    if missing_http_probes:
        raise RuntimeError(f"runtime state http probes missing: {missing_http_probes}")
    return (
        "feature read contracts are available",
        {
            "runtimeConfigKeys": required_config_keys,
            "httpProbes": http_probes,
            "scenarioSmokeRequired": [
                "settings-apply",
                "update-apply",
                "redis-backup-restore",
                "runtime-data-backup-restore",
                "observability-event-append",
                "product-lab-recorder-flow",
                "export-logs",
                "clean-uninstall-reset",
            ],
        },
    )


def systemd_active_state(run: RuntimeBootSmokeRun, service: str) -> str:
    return systemd_property(run, service, "ActiveState")


def systemd_result(run: RuntimeBootSmokeRun, service: str) -> str:
    return systemd_property(run, service, "Result")


def systemd_property(run: RuntimeBootSmokeRun, service: str, property_name: str) -> str:
    completed = run.operations.run(
        ["systemctl", "show", f"--property={property_name}", "--value", service],
        check=False,
        capture_output=True,
        timeout_seconds=SYSTEMD_TIMEOUT_SECONDS,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"failed to read systemd unit property: {service}.{property_name}: "
            f"{completed.stderr.strip() or completed.returncode}"
        )
    value = (completed.stdout or "").strip()
    if not value:
        raise RuntimeError(f"systemd unit property is empty: {service}.{property_name}")
    return value


def runtime_state_document(runtime_state: dict[str, Any]) -> dict[str, Any]:
    document = runtime_state.get("document")
    if not isinstance(document, dict):
        raise RuntimeError("runtime state document is missing from stage details")
    return document


def read_current_runtime_state_document(
    run: RuntimeBootSmokeRun,
    bootstrap_result: dict[str, Any],
) -> dict[str, Any]:
    return runtime_state_document(
        validate_runtime_state(run, bootstrap_result)[1],
    )


def expected_compose_service_requirements(
    dev_build: bool,
) -> tuple[ComposeServiceRequirement, ...]:
    del dev_build
    expected = [
        ComposeServiceRequirement(name=name)
        for name in BASE_REQUIRED_COMPOSE_SERVICES
    ]
    return tuple(expected)


def read_guest_control_stack_status(run: RuntimeBootSmokeRun) -> dict[str, Any]:
    document = run.operations.http_json(
        "GET",
        f"{GUEST_CONTROL_API_BASE_URL}/v1/stack/status",
        HTTP_TIMEOUT_SECONDS,
        None,
    )
    require_equal(
        document.get("state"),
        "loaded",
        "guest control API stack status is not loaded",
    )
    observed_at = require_non_empty_string(
        document.get("observedAt"),
        "guest control API stack status observedAt",
    )
    document_age_seconds(observed_at, run.operations.now())
    return document


def observed_stack_services(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    services = document.get("services")
    if not isinstance(services, list) or not services:
        raise RuntimeError("guest control API stack status services are missing")
    observed: dict[str, dict[str, Any]] = {}
    for service in services:
        if not isinstance(service, dict):
            continue
        name = service.get("service")
        if isinstance(name, str) and name:
            observed[name] = service
    return observed


def unhealthy_compose_services(
    expected: tuple[ComposeServiceRequirement, ...],
    observed: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    unhealthy = []
    for requirement in sorted(expected, key=lambda item: item.name):
        service = observed[requirement.name]
        if service_is_ready(service, requirement=requirement):
            continue
        unhealthy.append(
            {
                "service": requirement.name,
                "state": service.get("state"),
                "health": service.get("health"),
                "exitCode": service.get("exitCode"),
            }
        )
    return unhealthy


def missing_compose_services(
    expected: tuple[ComposeServiceRequirement, ...],
    observed: dict[str, dict[str, Any]],
) -> list[str]:
    observed_names = set(observed)
    return sorted(
        requirement.name
        for requirement in expected
        if requirement.name not in observed_names
    )


def service_is_ready(
    service: dict[str, Any],
    *,
    requirement: ComposeServiceRequirement,
) -> bool:
    state = service.get("state")
    health = service.get("health")
    exit_code = service.get("exitCode")
    if state != "running":
        return False
    if exit_code not in (None, 0, "0", ""):
        return False
    if requirement.require_healthy:
        return health == "healthy"
    return True


def run_command(
    arguments: list[str],
    *,
    check: bool = True,
    capture_output: bool = False,
    timeout_seconds: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments,
        check=check,
        capture_output=capture_output,
        text=True,
        timeout=timeout_seconds,
    )


def http_status(url: str, timeout_seconds: float) -> int:
    request = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except (OSError, TimeoutError, urllib.error.URLError) as error:
        raise RuntimeError(f"HTTP probe failed: {url}: {error}") from error


def http_json(
    method: str,
    url: str,
    timeout_seconds: float,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = body if body is not None else ({} if method == "POST" else None)
    request = urllib.request.Request(
        url,
        data=None if payload is None else json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            payload = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        payload = error.read().decode("utf-8")
        raise RuntimeError(
            f"runtime HTTP JSON request failed: {method} {url} "
            f"status={error.code} body={payload}"
        ) from error
    except (OSError, TimeoutError, urllib.error.URLError) as error:
        raise RuntimeError(
            f"runtime HTTP JSON request failed: {method} {url}: {error}"
        ) from error
    try:
        document = json.loads(payload)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"runtime HTTP JSON response is invalid: {method} {url}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise RuntimeError(
            f"runtime HTTP JSON response must be an object: {method} {url}"
        )
    return document


def read_required_json_object(path: Path, subject: str) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError(f"{subject} is missing: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise RuntimeError(f"{subject} is unreadable: {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError(f"{subject} is invalid JSON: {path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{subject} must be a JSON object: {path}")
    return value


def require_equal(actual: object, expected: object, message: str) -> None:
    if actual != expected:
        raise RuntimeError(f"{message}: expected={expected} actual={actual}")


def require_non_empty_string(value: object, subject: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise RuntimeError(f"{subject} is missing")
    return value


def document_age_seconds(updated_at: str, now: datetime) -> float:
    try:
        parsed = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise RuntimeError(f"timestamp is invalid: {updated_at}") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return max((now - parsed.astimezone(UTC)).total_seconds(), 0.0)


def list_value(value: object) -> list[object]:
    return value if isinstance(value, list) else []
