#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CheckResult:
    name: str
    ok: bool
    detail: str


ROOT = Path(__file__).resolve().parents[1]
MACOS_RUNTIME = ROOT / "apps/vitalserver-macos-runtime"
GUEST_TOOLS = ROOT / "packages/vitalserver-guest-tools"
PWA = ROOT / "apps/vitalserver-runtime-pwa"


def main() -> int:
    results = [
        check_runtime_status_reader_uses_guest_control(),
        check_runtime_container_observation_does_not_expose_compose_services(),
        check_runtime_status_assembly_does_not_promote_runtime_state_services(),
        check_runtime_status_document_has_no_container_observation(),
        check_runtime_event_contract_has_no_container_observation(),
        check_runtime_event_factory_does_not_write_container_observation(),
        check_host_failure_reasons_do_not_model_container_observation_reads(),
        check_runtime_state_document_has_no_container_services(),
        check_runtime_state_document_has_no_capabilities(),
        check_runtime_guest_runtime_state_policy_is_removed(),
        check_runtime_guest_file_gateway_is_maintenance_only(),
        check_legacy_guest_request_result_file_names_are_removed(),
        check_swift_legacy_guest_result_documents_are_removed(),
        check_guest_request_file_poller_is_removed(),
        check_redis_backup_file_bridge_is_runtime_state_watcher_only(),
        check_redis_backup_has_guest_control_maintenance_api(),
        check_update_activation_has_guest_control_maintenance_api(),
        check_update_shutdown_has_guest_control_maintenance_api(),
        check_host_update_activation_uses_guest_control_api(),
        check_host_update_shutdown_uses_guest_control_api(),
        check_host_redis_backup_create_uses_guest_control_api(),
        check_host_redis_restore_uses_guest_control_api(),
        check_host_datastore_repair_uses_guest_control_api(),
        check_cli_datastore_repair_uses_guest_control_api(),
        check_cli_redis_backup_restore_use_guest_control_api(),
        check_runtime_data_backup_uses_guest_control_maintenance_api(),
        check_product_surfaces_do_not_expose_dev_testkit(),
        check_runtime_control_api_exposes_v2_product_surface(),
        check_guest_control_lab_boundary_does_not_name_testkit(),
        check_guest_control_default_state_is_postgres_backed(),
        check_guest_service_operations_persist_status_snapshots(),
        check_guest_service_control_is_controller_owned_resource(),
        check_runtime_config_does_not_enable_testkit(),
        check_product_packaging_uses_lab_not_testkit(),
        check_vitaldb_read_models_do_not_name_host_sqlite_as_source(),
        check_vitaldb_host_sqlite_projection_requires_diagnostics_mode(),
        check_host_does_not_write_vitaldb_sqlite_projection(),
        check_host_health_does_not_promote_vitaldb_read_model_failures(),
        check_host_health_uses_guest_control_ready_for_guest_readiness(),
        check_host_proxy_runtime_state_read_is_vm_bootstrap_only(),
        check_current_health_filters_legacy_runtime_state_vm_errors(),
        check_managed_operation_guard_does_not_read_runtime_state(),
        check_guest_bootstrap_current_boot_uses_vm_lifecycle(),
        check_health_recovery_policies_do_not_accept_diagnostics_observations(),
        check_health_snapshot_contract_does_not_carry_container_observation(),
        check_runtime_status_document_does_not_store_vitaldb_observation(),
        check_runtime_status_contract_has_no_vitaldb_observation(),
        check_recorder_ingress_status_is_guest_control_only(),
        check_recorder_ingress_does_not_read_runtime_state_memory_guard(),
        check_runtime_boot_smoke_uses_guest_control_stack_status(),
        check_runtime_proof_acceptance_targets_are_explicit(),
        check_runtime_control_client_does_not_expose_whole_stack_start_stop(),
        check_runtime_control_http_does_not_expose_whole_stack_start_stop(),
        check_host_runtime_service_control_is_host_only(),
        check_swift_product_ui_does_not_expose_whole_stack_start_stop(),
        check_swift_product_lab_commands_require_lab_capability(),
        check_swift_event_display_does_not_promote_container_observation(),
        check_swift_guest_readiness_presentation_does_not_use_runtime_state(),
        check_guest_service_control_has_separate_capability(),
        check_guest_capability_checks_use_guest_control_api(),
        check_cli_consumes_guest_control_product_apis(),
        check_product_readmes_do_not_promote_legacy_sources(),
        check_testkit_package_is_dev_tooling_only(),
        check_runtime_proof_local_artifacts_and_private_samples_are_ignored(),
        check_product_docs_do_not_promote_testkit_runtime_surface(),
        check_runtime_proof_docs_describe_acceptance_targets(),
        check_api_catalog_exposes_runtime_support_specs(),
        check_runtime_proof_troubleshooting_documents_acceptance_blockers(),
        check_maintenance_docs_do_not_promote_request_files_as_current_path(),
        check_observer_docs_use_guest_postgres_read_model_flow(),
        check_redis_backup_restore_results_do_not_carry_request_id(),
        check_guest_tools_legacy_operation_result_model_removed(),
    ]

    failed = [result for result in results if not result.ok]
    for result in results:
        status = "passed" if result.ok else "failed"
        print(f"[{status}] {result.name}: {result.detail}")

    if failed:
        print("\nRuntime v2 no-v1-service-state check failed:", file=sys.stderr)
        for result in failed:
            print(f"  - {result.name}: {result.detail}", file=sys.stderr)
        return 1
    return 0


def check_runtime_status_reader_uses_guest_control() -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeStatusReader.swift"
    )
    text = read(path)
    required = [
        "gateway.stackStatus()",
        "gateway.serviceResource(",
        "RuntimeGuestServicesRead",
        "guestServiceResources",
        "guestServiceResourceReadIssues",
    ]
    forbidden = [
        "containerServices",
        "composeServices",
        "service-stack-status",
        "serviceStackStatus",
        "runtime-state.json",
        "GuestRuntimeStateDocumentReader",
        "paths.runtimeState",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if missing or present:
        return CheckResult(
            "runtime-status-reader-guest-control-source",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-status-reader-guest-control-source",
        True,
        "product service liveness and controller resources are read from Guest Control API "
        f"path={relative(path)}",
    )


def check_runtime_container_observation_does_not_expose_compose_services(
) -> CheckResult:
    paths = [
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared/RuntimeContainerObservation.swift"
        ),
        (
            PWA
            / "src/domain/runtime-control/contracts/generated/runtime-control.ts"
        ),
        (
            PWA
            / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
        ),
        ROOT / "docs/runtime/macos/runtime-control.openapi.json",
    ]
    forbidden = [
        "public struct RuntimeContainerObservation",
        "RuntimeContainerObservation",
        "composeServices",
        "composeServicesReadState",
        "composeServicesReadError",
        "RuntimeContainerServicesReadState",
    ]
    matches = find_tokens([path for path in paths if path.exists()], forbidden)
    if matches:
        return CheckResult(
            "runtime-container-observation-no-compose-services",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-container-observation-no-compose-services",
        True,
        (
            "RuntimeContainerObservation is not a production contract and "
            "container diagnostics contracts do not expose compose service state"
        ),
    )


def check_runtime_status_assembly_does_not_promote_runtime_state_services(
) -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift"
    )
    text = read(path)
    forbidden = [
        "GuestRuntimeStateRead",
        "GuestRuntimeStateDocument",
        "guestStateRead",
        "guestState?.",
        "guestState?.containerServices",
        "containerMemoryUsage(",
        'service: "app"',
        'service: "recorder-ingress"',
        'service: "redis"',
    ]
    present = [token for token in forbidden if token in text]
    if present:
        return CheckResult(
            "runtime-status-assembly-no-runtime-state-services",
            False,
            f"forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-status-assembly-no-runtime-state-services",
        True,
        "runtime-state documents are not status assembly inputs "
        f"path={relative(path)}",
    )


def check_runtime_status_document_has_no_container_observation() -> CheckResult:
    paths = {
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeStatusDocument.swift": [
            "containerObservation",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Domain/Models/RuntimeStatusDocumentBuilder.swift"
        ): [
            "containerObservation:",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Application/UseCases/RuntimeOperationReporting"
            / "BuildRuntimeStatusDocumentUseCase.swift"
        ): [
            "containerObservation:",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Application/UseCases/Observability"
            / "RuntimeEventFactory.swift"
        ): [
            "statusDocument.containerObservation",
        ],
    }
    matches: list[str] = []
    for path, tokens in paths.items():
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token}")
    if matches:
        return CheckResult(
            "runtime-status-document-no-container-observation",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-status-document-no-container-observation",
        True,
        "runtime-status.json no longer carries container diagnostics evidence",
    )


def check_runtime_event_contract_has_no_container_observation() -> CheckResult:
    paths = [
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeEventDocument.swift",
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts",
        PWA
        / "src/domain/runtime-control/contracts/generated/runtime-control.ts",
        ROOT / "docs/runtime/macos/runtime-control.openapi.json",
    ]
    forbidden = [
        "containerObservation",
        "RuntimeContainerObservation",
        "runtimeContainerObservationSchema",
        "RuntimeFileMetadataReadState",
    ]
    matches = find_tokens([path for path in paths if path.exists()], forbidden)
    if matches:
        return CheckResult(
            "runtime-event-contract-no-container-observation",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-event-contract-no-container-observation",
        True,
        "Runtime event contracts do not carry container diagnostics",
    )


def check_runtime_event_factory_does_not_write_container_observation(
) -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/Observability/RuntimeEventFactory.swift"
    )
    text = read(path)
    forbidden = [
        "containerObservation: healthSnapshot.containerObservation",
        "healthSnapshot.containerObservation",
    ]
    present = [token for token in forbidden if token in text]
    if present:
        return CheckResult(
            "runtime-event-factory-no-container-observation-write",
            False,
            f"forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-event-factory-no-container-observation-write",
        True,
        "new runtime events do not write container diagnostics from health snapshots",
    )


def check_host_failure_reasons_do_not_model_container_observation_reads(
) -> CheckResult:
    paths = [
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared/RuntimeFailureReason.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Domain/Policies/RuntimeWatchdogRecoveryPolicy.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Copy"
            / "AppConstants+StatusText.swift"
        ),
    ]
    forbidden = [
        "containerObservationMissing",
        "containerObservationReadFailed",
        "isContainerObservationReadFailureFromStaleGuestRuntimeState",
        "container-observation-missing",
        "container-observation-read-failed",
    ]
    matches = find_tokens(paths, forbidden)
    if matches:
        return CheckResult(
            "host-failure-reasons-no-container-observation-reads",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "host-failure-reasons-no-container-observation-reads",
        True,
        (
            "Host failure reasons do not model container observation "
            "missing/read failures"
        ),
    )


def check_runtime_state_document_has_no_container_services() -> CheckResult:
    checks = {
        MACOS_RUNTIME / "Sources/Contracts/Shared/GuestRuntimeStateDocument.swift": [
            "containerServices",
            "RuntimeContainerServiceObservation",
            "vitalDBObservation",
            "VitalDBObservationDocument",
        ],
        GUEST_TOOLS / "src/tirosh_guest_tools/domain/runtime_state.py": [
            '"containerServices"',
            "container_services:",
            "RuntimeContainerService",
            '"vitalDBObservation"',
            "vitaldb_observation",
        ],
        GUEST_TOOLS / "src/tirosh_guest_tools/adapters/outbound/runtime/collector.py": [
            "container_services=compose_services(",
            "def compose_services(",
            "docker compose ps",
            "docker stats",
            "docker inspect",
            "ContainerInspection",
            "ContainerMemoryStats",
        ],
    }
    matches: list[str] = []
    for path, tokens in checks.items():
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token}")
    if matches:
        return CheckResult(
            "runtime-state-document-no-container-services",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-state-document-no-container-services",
        True,
        (
            "runtime-state.json no longer carries container service or "
            "VitalDB observation state"
        ),
    )


def check_runtime_state_document_has_no_capabilities() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Contracts/Shared/GuestRuntimeStateDocument.swift",
        GUEST_TOOLS / "src/tirosh_guest_tools/domain/runtime_state.py",
        GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_boot_smoke.py",
        GUEST_TOOLS / "tests/test_runtime_boot_smoke.py",
    ]
    forbidden = [
        "GuestRuntimeCapabilities",
        "RuntimeCapabilities",
        '"capabilities": self.capabilities.as_json()',
        "runtime state capabilities",
        "REQUIRED_CAPABILITIES",
    ]
    matches = find_tokens(paths, forbidden)
    required_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/runtime_boot_smoke.py"
    )
    text = read(required_path)
    required = [
        "REQUIRED_GUEST_CONTROL_CAPABILITIES",
        "require_guest_control_capabilities",
        "GUEST_CONTROL_API_BASE_URL}/v1/capabilities",
        '"source": "guest-control-api"',
    ]
    missing = [token for token in required if token not in text]
    if matches or missing:
        return CheckResult(
            "runtime-state-document-no-capabilities",
            False,
            f"matches={matches[:10]} missing={missing}",
        )
    return CheckResult(
        "runtime-state-document-no-capabilities",
        True,
        "runtime-state.json no longer carries capability state; "
        "boot smoke checks Guest Control /v1/capabilities",
    )


def check_runtime_guest_runtime_state_policy_is_removed() -> CheckResult:
    paths = [
        (
            MACOS_RUNTIME
            / "Sources/Domain/Policies/RuntimeGuestRuntimeStatePolicy.swift"
        ),
        (
            MACOS_RUNTIME
            / "Tests/DomainTests/Policies/RuntimeGuestRuntimeStatePolicyTests.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Health"
            / "RuntimeGuestRuntimeStateObservationReader.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared"
            / "RuntimeGuestRuntimeStateObservationAssembly.swift"
        ),
        (
            MACOS_RUNTIME
            / "Tests/ContractsTests"
            / "RuntimeGuestRuntimeStateObservationAssemblerTests.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared"
            / "RuntimeGuestRuntimeStateInput.swift"
        ),
    ]
    present = [relative(path) for path in paths if path.exists()]
    source_root = MACOS_RUNTIME / "Sources"
    forbidden = [
        "public struct RuntimeGuestRuntimeStateObservation",
        "public enum RuntimeGuestRuntimeStateReadIssue",
        "RuntimeGuestRuntimeStateObservationReader",
        "RuntimeGuestRuntimeStateObservationAssembler",
        "RuntimeGuestRuntimeStateInput",
        "RuntimeGuestRuntimeStateInputPlan",
        "guestRuntimeStateInputPlan(",
        "guestRuntimeState:",
        "observation.guestRuntimeState",
        "RuntimeGuestRuntimeStateDiagnosticsReader",
        "loadRuntimeStateDiagnosticsDocument",
        "guestRuntimeStateDiagnosticsReader",
        "runtimeStateURL:",
        "runtimeStateStaleAfterSeconds",
    ]
    matches = find_tokens([source_root], forbidden)
    if present:
        return CheckResult(
            "runtime-guest-runtime-state-policy-removed",
            False,
            f"present={present}",
        )
    if matches:
        return CheckResult(
            "runtime-guest-runtime-state-policy-removed",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-guest-runtime-state-policy-removed",
        True,
        "Host health no longer keeps runtime-state.json guestHTTP/vmIP "
        "promotion or runtime-state freshness observation paths",
    )


def check_runtime_guest_file_gateway_is_maintenance_only() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Application/Ports/RuntimeGuestDocumentReaders.swift",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence"
            / "JSONFileRuntimeGuestDocumentReader.swift"
        ),
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeFileNames.swift",
        MACOS_RUNTIME / "Sources/Bootstrap/Composition/Constants.swift",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/FileSystem/InstalledRuntimePaths.swift"
        ),
    ]
    text = "\n".join(read(path) for path in paths)
    forbidden = [
        "reconcile-compose",
        "reconcileCompose",
        "ReconcileCompose",
        "reconcileGuestCompose",
        "writeUpdateActivationRequest",
        "writeUpdateShutdownRequest",
        "loadUpdateActivationResultDocument",
        "loadUpdateShutdownResultDocument",
        "removeUpdateActivationResult",
        "removeUpdateShutdownResult",
        "clearUpdateShutdownPreparation",
        "writeDatastoreRepairRequest",
        "loadDatastoreRepairResultDocument",
        "removeDatastoreRepairResult",
        "writeRedisRestoreRequest",
        "loadRedisRestoreResultDocument",
        "removeRedisRestoreResult",
        "datastoreRepairRequest",
        "datastoreRepairResult",
        "redisRestoreRequest",
        "redisRestoreResult",
        "updateActivationRequest",
        "updateActivationResult",
        "updateShutdownRequest",
        "updateShutdownResult",
        "repair-datastore.request",
        "repair-datastore-result.json",
        "redis-restore.request",
        "redis-restore-result.json",
        "activate-update.request",
        "activate-update-result.json",
        "prepare-update-shutdown.request",
        "prepare-update-shutdown-result.json",
        "TestKit",
        "testkit",
        "writeService",
        "loadService",
        "writeStack",
        "loadStack",
        "RuntimeGuestGateway",
        "JSONFileRuntimeGuestGateway",
        "loadRuntimeStateDocument",
        "RuntimeGuestRuntimeStateDiagnosticsReader",
        "loadRuntimeStateDiagnosticsDocument",
        "guestRuntimeStateDiagnosticsReader",
        "runtimeStateURL:",
        "typealias RuntimeGuestDocumentReader",
    ]
    required = [
        "RuntimeGuestBootstrapResultReader",
        "loadBootstrapResultDocument",
    ]
    present = [token for token in forbidden if token in text]
    missing = [token for token in required if token not in text]
    if present or missing:
        return CheckResult(
            "runtime-guest-file-gateway-maintenance-only",
            False,
            f"forbidden_present={present} missing={missing}",
        )
    return CheckResult(
        "runtime-guest-file-gateway-maintenance-only",
        True,
        "document readers expose only role-specific bootstrap proof reads",
    )


def check_legacy_guest_request_result_file_names_are_removed() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeFileNames.swift",
        MACOS_RUNTIME / "Sources/Bootstrap/Composition/Constants.swift",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/FileSystem/InstalledRuntimePaths.swift"
        ),
        GUEST_TOOLS / "src/tirosh_guest_tools/contracts.py",
        (
            GUEST_TOOLS
            / "src/tirosh_guest_tools/infrastructure/bootstrap_operations.py"
        ),
    ]
    legacy_tokens = [
        "reconcile-compose.request",
        "reconcile-compose-result.json",
        "redis-backup.request",
        "redis-backup-result.json",
        "redis-restore.request",
        "redis-restore-result.json",
        "repair-datastore.request",
        "repair-datastore-result.json",
        "activate-update.request",
        "activate-update-result.json",
        "prepare-update-shutdown.request",
        "prepare-update-shutdown-result.json",
        "RECORDER_INGRESS_RUNTIME_STATE_PATH",
        "RECORDER_INGRESS_RUNTIME_STATE_MAX_AGE_MS",
    ]
    matches = find_tokens(paths, legacy_tokens)
    if matches:
        return CheckResult(
            "legacy-guest-request-result-file-names-removed",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "legacy-guest-request-result-file-names-removed",
        True,
        "shared Host/Guest contracts no longer publish v1 request/result file names",
    )


def check_swift_legacy_guest_result_documents_are_removed() -> CheckResult:
    source_root = MACOS_RUNTIME / "Sources"
    forbidden = [
        "GuestActivationEvaluator",
        "GuestShutdownEvaluator",
        "DatastoreRepairEvaluator",
        "GuestActivationWaiter",
        "GuestShutdownWaiter",
        "DatastoreRepairWaiter",
        "GuestUpdateActivationResultDocument",
        "GuestUpdateShutdownResultDocument",
        "DatastoreRepairResultDocument",
        "GuestUpdateActivationRequestDocument",
        "GuestUpdateShutdownRequestDocument",
        "RuntimeGuestActivationRequest",
        "RuntimeGuestShutdownRequest",
        "RuntimeDatastoreRepairRequest",
        "RuntimeGuestRequests.swift",
        "GuestActivationStatus",
        "GuestShutdownStatus",
        "GuestShutdownPhase",
        "DatastoreRepairStatus",
        "GuestActivationDocuments.swift",
        "GuestShutdownDocuments.swift",
        "DatastoreRepairDocuments.swift",
        "activate-update-result",
        "prepare-update-shutdown-result",
        "repair-datastore-result",
    ]
    matches: list[str] = []
    for path in sorted(source_root.rglob("*.swift")):
        text = read(path)
        for token in forbidden:
            if token in text:
                matches.append(f"{relative(path)}:{token}")
    deleted_files = [
        source_root / "Contracts/Shared/GuestActivationDocuments.swift",
        source_root / "Contracts/Shared/GuestShutdownDocuments.swift",
        source_root / "Contracts/Shared/DatastoreRepairDocuments.swift",
        source_root / "Contracts/Shared/RuntimeGuestRequests.swift",
        source_root / "Domain/Policies/GuestActivationEvaluator.swift",
        source_root / "Domain/Policies/GuestShutdownEvaluator.swift",
        source_root / "Domain/Policies/DatastoreRepairEvaluator.swift",
    ]
    existing = [relative(path) for path in deleted_files if path.exists()]
    if matches or existing:
        return CheckResult(
            "swift-legacy-guest-result-documents-removed",
            False,
            f"matches={matches[:10]} existing={existing}",
        )
    return CheckResult(
        "swift-legacy-guest-result-documents-removed",
        True,
        "Swift production source has no legacy guest request/result documents",
    )


def check_guest_request_file_poller_is_removed() -> CheckResult:
    path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/request_file_poller.py"
    )
    pyproject = GUEST_TOOLS / "pyproject.toml"
    bootstrap_operations = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/infrastructure/bootstrap_operations.py"
    )
    support_paths = [
        MACOS_RUNTIME / "Support/Guest/bin/tirosh-vitalserver-command-poller",
        (
            MACOS_RUNTIME
            / "Support/Guest/systemd/tirosh-vitalserver-command-poller.service"
        ),
    ]
    existing = [
        relative(candidate)
        for candidate in [path, *support_paths]
        if candidate.exists()
    ]
    text = read(pyproject) + "\n" + read(bootstrap_operations)
    forbidden = [
        "tirosh-vitalserver-command-poller",
        "COMMAND_POLLER",
        "request_file_poller",
    ]
    present = [token for token in forbidden if token in text]
    if existing or present:
        return CheckResult(
            "guest-request-file-poller-removed",
            False,
            f"existing={existing} forbidden_present={present}",
        )
    return CheckResult(
        "guest-request-file-poller-removed",
        True,
        "guest command request-file poller is removed from v2 runtime",
    )


def check_redis_backup_file_bridge_is_runtime_state_watcher_only() -> CheckResult:
    runtime_state_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_state.py"
    )
    redis_backup_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/redis_backup.py"
    )
    contracts_path = GUEST_TOOLS / "src/tirosh_guest_tools/contracts.py"
    bootstrap_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/infrastructure/bootstrap_operations.py"
    )
    update_shutdown_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/update_shutdown.py"
    )
    redis_backup_service_path = (
        MACOS_RUNTIME
        / "Support/Guest/systemd/tirosh-vitalserver-redis-backup.service"
    )
    runtime_state = read(runtime_state_path)
    redis_backup = read(redis_backup_path)
    contracts = read(contracts_path)
    bootstrap = read(bootstrap_path)
    update_shutdown = read(update_shutdown_path)
    forbidden_by_path = {
        relative(runtime_state_path): [
            "REDIS_BACKUP_REQUEST_FILE",
            "trigger_redis_backup_if_requested",
            "RuntimeService.REDIS_BACKUP.value",
        ],
        relative(redis_backup_path): [
            "REQUEST_FILE",
            "RESULT_FILE",
            "request_id_from",
            "write_result(",
            "GuestOperationResult",
            "OperationName.REDIS_BACKUP",
            "OperationStatus.",
        ],
        relative(contracts_path): [
            "REDIS_BACKUP_REQUEST",
            "REDIS_BACKUP_RESULT",
            'REDIS_BACKUP = "tirosh-vitalserver-redis-backup.service"',
        ],
        relative(bootstrap_path): [
            '"tirosh-vitalserver-redis-backup.service"',
        ],
        relative(update_shutdown_path): [
            "REDIS_BACKUP_ACTIVE_WAIT_TIMEOUT_SECONDS",
            "RuntimeService.REDIS_BACKUP",
        ],
        relative(redis_backup_service_path): [
            "ExecStart=/usr/local/bin/tirosh-vitalserver-redis-backup",
        ],
    }
    texts = {
        relative(runtime_state_path): runtime_state,
        relative(redis_backup_path): redis_backup,
        relative(contracts_path): contracts,
        relative(bootstrap_path): bootstrap,
        relative(update_shutdown_path): update_shutdown,
        relative(redis_backup_service_path): (
            read(redis_backup_service_path)
            if redis_backup_service_path.exists()
            else ""
        ),
    }
    present = {
        path: [token for token in tokens if token in texts[path]]
        for path, tokens in forbidden_by_path.items()
        if any(token in texts[path] for token in tokens)
    }
    if present:
        return CheckResult(
            "redis-backup-file-bridge-runtime-state-watcher-only",
            False,
            f"forbidden_present={present}",
        )
    return CheckResult(
        "redis-backup-file-bridge-runtime-state-watcher-only",
        True,
        "redis backup no longer has a request/result file bridge or systemd "
        "sidecar service",
    )


def check_redis_backup_has_guest_control_maintenance_api() -> CheckResult:
    api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    usecase_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    model_path = GUEST_TOOLS / "src/tirosh_guest_tools/domain/guest_control/models.py"
    adapter_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/maintenance/redis_backup.py"
    )
    restore_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/redis_restore.py"
    )
    contracts_path = GUEST_TOOLS / "src/tirosh_guest_tools/contracts.py"
    api = read(api_path)
    usecase = read(usecase_path)
    model = read(model_path)
    adapter = read(adapter_path)
    restore = read(restore_path)
    contracts = read(contracts_path)
    required_by_path = {
        api_path: [
            '["v1", "maintenance", "redis-backup"]',
            '["v1", "maintenance", "redis-restore"]',
            "create_redis_backup().as_json()",
            "restore_redis_backup(",
            "RedisBackupMaintenanceAdapter()",
        ],
        usecase_path: [
            "def create_redis_backup(",
            "def restore_redis_backup(",
            '"maintenance:redis-backup:create"',
            '"maintenance:redis-restore:create"',
            "ServiceCommand.REDIS_BACKUP",
            "ServiceCommand.REDIS_RESTORE",
            "result=backup_result.as_json()",
            "result=restore_result.as_json()",
            "RedisBackupDependencyError",
            "RedisRestoreDependencyError",
        ],
        model_path: [
            'REDIS_BACKUP = "redis-backup"',
            'REDIS_RESTORE = "redis-restore"',
            "class RedisBackupResult",
            "class RedisRestoreResult",
            "result: dict[str, Any] | None = None",
        ],
        adapter_path: [
            "class RedisBackupMaintenanceAdapter",
            "run_redis_backup()",
            "restore_redis_archive(Path(archive))",
            "RedisBackupDependencyError",
            "RedisRestoreDependencyError",
        ],
    }
    texts = {
        api_path: api,
        usecase_path: usecase,
        model_path: model,
        adapter_path: adapter,
    }
    missing = {
        relative(path): [token for token in tokens if token not in texts[path]]
        for path, tokens in required_by_path.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden_by_path = {
        relative(restore_path): [
            "run_redis_restore",
            "REQUEST_FILE",
            "RESULT_FILE",
            "read_request(",
            "write_result(",
            "OperationName.REDIS_RESTORE",
            "OperationStatus.",
        ],
        relative(contracts_path): [
            "REDIS_RESTORE_REQUEST",
            "REDIS_RESTORE_RESULT",
            "REDIS_RESTORE = \"tirosh-vitalserver-redis-restore.service\"",
        ],
    }
    forbidden_texts = {
        relative(restore_path): restore,
        relative(contracts_path): contracts,
    }
    present = {
        path: [token for token in tokens if token in forbidden_texts[path]]
        for path, tokens in forbidden_by_path.items()
        if any(token in forbidden_texts[path] for token in tokens)
    }
    if missing or present:
        return CheckResult(
            "redis-backup-guest-control-maintenance-api",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "redis-backup-guest-control-maintenance-api",
        True,
        "redis backup and restore are exposed as Guest Control maintenance APIs",
    )


def check_update_activation_has_guest_control_maintenance_api() -> CheckResult:
    api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    usecase_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    port_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/ports.py"
    )
    model_path = GUEST_TOOLS / "src/tirosh_guest_tools/domain/guest_control/models.py"
    adapter_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/maintenance"
        / "update_activation.py"
    )
    activation_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/update_activation.py"
    )
    contracts_path = GUEST_TOOLS / "src/tirosh_guest_tools/contracts.py"
    bootstrap_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/infrastructure/bootstrap_operations.py"
    )
    observability_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/observability/collectors.py"
    )
    texts = {
        api_path: read(api_path),
        usecase_path: read(usecase_path),
        port_path: read(port_path),
        model_path: read(model_path),
        adapter_path: read(adapter_path),
        activation_path: read(activation_path),
        contracts_path: read(contracts_path),
        bootstrap_path: read(bootstrap_path),
        observability_path: read(observability_path),
    }
    required_by_path = {
        api_path: [
            '["v1", "maintenance", "update-activation"]',
            "usecases.activate_update(",
            "UpdateActivationMaintenanceAdapter()",
        ],
        usecase_path: [
            "def activate_update(",
            '"maintenance:update-activation:create"',
            "ServiceCommand.UPDATE_ACTIVATION",
            'service="update-activation"',
            "result=activation_result.as_json()",
            "UpdateActivationDependencyError",
        ],
        port_path: [
            "class UpdateActivationPort",
            "def activate_update(",
            "UpdateActivationResult",
        ],
        model_path: [
            'UPDATE_ACTIVATION = "activate-update"',
            "class UpdateActivationDependencyError",
            "class UpdateActivationResult",
        ],
        adapter_path: [
            "class UpdateActivationMaintenanceAdapter",
            "activate_runtime()",
            "UpdateActivationDependencyError",
            "UpdateActivationResult",
        ],
        activation_path: [
            "def run_activate_update()",
            "activate_runtime()",
            "def activate_runtime()",
        ],
    }
    missing = {
        relative(path): [token for token in tokens if token not in texts[path]]
        for path, tokens in required_by_path.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden_by_path = {
        activation_path: [
            "REQUEST_FILE",
            "RESULT_FILE",
            "request_id_from",
            "request_version_from",
            "write_result(",
            "OperationName.ACTIVATE_UPDATE",
            "OperationStatus.",
        ],
        contracts_path: [
            "ACTIVATE_UPDATE_REQUEST",
            "ACTIVATE_UPDATE_RESULT",
            'ACTIVATE_UPDATE = "tirosh-vitalserver-activate-update.service"',
        ],
        bootstrap_path: [
            '"tirosh-vitalserver-activate-update.service"',
        ],
        observability_path: [
            "ACTIVATE_UPDATE_REQUEST",
            "ACTIVATE_UPDATE_RESULT",
        ],
    }
    present = {
        relative(path): [token for token in tokens if token in texts[path]]
        for path, tokens in forbidden_by_path.items()
        if any(token in texts[path] for token in tokens)
    }
    if missing or present:
        return CheckResult(
            "update-activation-guest-control-maintenance-api",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "update-activation-guest-control-maintenance-api",
        True,
        "update activation is exposed as a Guest Control maintenance API",
    )


def check_host_update_activation_uses_guest_control_api() -> CheckResult:
    composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeGuestActivationComposition.swift"
    )
    lifecycle_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Support"
        / "RuntimeLifecycle+ServiceSupport.swift"
    )
    repair_composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Lifecycle"
        / "RuntimeLifecycle+RepairComposition.swift"
    )
    gateway_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/GuestControl"
        / "HTTPRuntimeGuestControlGateway.swift"
    )
    usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeServices"
        / "RuntimeGuestMaintenanceControlUseCase.swift"
    )
    guest_api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    texts = {
        composition_path: read(composition_path),
        lifecycle_path: read(lifecycle_path),
        repair_composition_path: read(repair_composition_path),
        gateway_path: read(gateway_path),
        usecase_path: read(usecase_path),
        guest_api_path: read(guest_api_path),
    }
    required_by_path = {
        composition_path: [
            "activateUpdate: operations.activateUpdate",
            "RuntimeGuestActivationWorkflowActions",
        ],
        lifecycle_path: [
            "func activateUpdateThroughGuestControl(",
            ".activateUpdate(",
            "RuntimeGuestMaintenanceControlUseCase()",
        ],
        repair_composition_path: [
            "activateUpdateThroughGuestControl(",
        ],
        gateway_path: [
            "func activateUpdate(requestId: String, version: String)",
            'path: "/v1/maintenance/update-activation"',
            "RuntimeGuestControlUpdateActivationRequest",
        ],
        usecase_path: [
            "activateUpdate(",
            "expectedService: \"update-activation\"",
            "expectedCommand: .updateActivation",
        ],
        guest_api_path: [
            '["v1", "maintenance", "update-activation"]',
        ],
    }
    missing = {
        relative(path): [token for token in tokens if token not in texts[path]]
        for path, tokens in required_by_path.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = [
        "removeActivationResult",
        "writeActivationRequest",
        "loadActivationResult",
        "removeUpdateActivationResult",
        "writeUpdateActivationRequest",
        "loadUpdateActivationResultDocument",
    ]
    activation_composition = texts[composition_path]
    forbidden_present = [
        token for token in forbidden if token in activation_composition
    ]
    if missing or forbidden_present:
        return CheckResult(
            "host-update-activation-guest-control-api",
            False,
            f"missing={missing} forbidden_present={forbidden_present}",
        )
    return CheckResult(
        "host-update-activation-guest-control-api",
        True,
        "Host update activation consumes Guest Control maintenance API",
    )


def check_host_update_shutdown_uses_guest_control_api() -> CheckResult:
    composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeGuestShutdownComposition.swift"
    )
    workflow_path = (
        MACOS_RUNTIME
        / "Sources/Workflow/RuntimeUpdateLifecycle"
        / "RuntimeGuestShutdownWorkflow.swift"
    )
    lifecycle_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Support"
        / "RuntimeLifecycle+ServiceSupport.swift"
    )
    repair_composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Lifecycle"
        / "RuntimeLifecycle+RepairComposition.swift"
    )
    gateway_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/GuestControl"
        / "HTTPRuntimeGuestControlGateway.swift"
    )
    usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeServices"
        / "RuntimeGuestMaintenanceControlUseCase.swift"
    )
    texts = {
        composition_path: read(composition_path),
        workflow_path: read(workflow_path),
        lifecycle_path: read(lifecycle_path),
        repair_composition_path: read(repair_composition_path),
        gateway_path: read(gateway_path),
        usecase_path: read(usecase_path),
    }
    required_by_path = {
        composition_path: [
            "prepareUpdateShutdown: operations.prepareUpdateShutdown",
            "loadOperation: operations.loadOperation",
            "requestGuestPoweroff: operations.requestGuestPoweroff",
        ],
        workflow_path: [
            "actions.prepareUpdateShutdown(",
            "actions.loadOperation(operation.operationId)",
            "actions.requestGuestPoweroff()",
            'operation.result?.shutdownPhase == "poweroff-ready"',
        ],
        lifecycle_path: [
            "func prepareUpdateShutdownThroughGuestControl(",
            "func requestGuestPoweroffThroughGuestControl()",
            "func guestControlOperationThroughGuestControl(",
        ],
        repair_composition_path: [
            "prepareUpdateShutdownThroughGuestControl(",
            "guestControlOperationThroughGuestControl(operationID)",
            "requestGuestPoweroffThroughGuestControl()",
        ],
        gateway_path: [
            "func prepareUpdateShutdown(requestId: String, version: String)",
            "func requestGuestPoweroff()",
            'path: "/v1/maintenance/update-shutdown"',
            'path: "/v1/maintenance/guest-poweroff"',
        ],
        usecase_path: [
            "prepareUpdateShutdown(",
            "requestGuestPoweroff(",
            "expectedService: \"update-shutdown\"",
            "expectedService: \"guest-poweroff\"",
        ],
    }
    missing = {
        relative(path): [token for token in tokens if token not in texts[path]]
        for path, tokens in required_by_path.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = [
        "removeShutdownResult",
        "writeShutdownRequest",
        "loadShutdownResult",
        "removeUpdateShutdownResult",
        "writeUpdateShutdownRequest",
        "loadUpdateShutdownResultDocument",
    ]
    combined = texts[composition_path] + "\n" + texts[workflow_path]
    forbidden_present = [token for token in forbidden if token in combined]
    if missing or forbidden_present:
        return CheckResult(
            "host-update-shutdown-guest-control-api",
            False,
            f"missing={missing} forbidden_present={forbidden_present}",
        )
    return CheckResult(
        "host-update-shutdown-guest-control-api",
        True,
        "Host update shutdown consumes Guest Control maintenance API",
    )


def check_update_shutdown_has_guest_control_maintenance_api() -> CheckResult:
    api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    usecase_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    port_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/ports.py"
    )
    model_path = GUEST_TOOLS / "src/tirosh_guest_tools/domain/guest_control/models.py"
    adapter_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/maintenance"
        / "update_shutdown.py"
    )
    shutdown_app_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/update_shutdown.py"
    )
    contracts_path = GUEST_TOOLS / "src/tirosh_guest_tools/contracts.py"
    bootstrap_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/infrastructure/bootstrap_operations.py"
    )
    collectors_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/observability/collectors.py"
    )
    texts = {
        api_path: read(api_path),
        usecase_path: read(usecase_path),
        port_path: read(port_path),
        model_path: read(model_path),
        adapter_path: read(adapter_path),
        shutdown_app_path: read(shutdown_app_path),
        contracts_path: read(contracts_path),
        bootstrap_path: read(bootstrap_path),
        collectors_path: read(collectors_path),
    }
    required_by_path = {
        api_path: [
            '["v1", "maintenance", "update-shutdown"]',
            "usecases.prepare_update_shutdown(",
            "UpdateShutdownMaintenanceAdapter()",
        ],
        usecase_path: [
            "def prepare_update_shutdown(",
            '"maintenance:update-shutdown:create"',
            "ServiceCommand.UPDATE_SHUTDOWN",
            'service="update-shutdown"',
            "def mark_ready(",
            "def mark_failed(",
            "on_ready=mark_ready",
            "on_failure=mark_failed",
        ],
        port_path: [
            "class UpdateShutdownPort",
            "def prepare_update_shutdown(",
            "on_ready: Callable[[UpdateShutdownResult], None]",
            "on_failure: Callable[[UpdateShutdownDependencyError], None]",
        ],
        model_path: [
            'UPDATE_SHUTDOWN = "prepare-update-shutdown"',
            "class UpdateShutdownDependencyError",
            "class UpdateShutdownResult",
        ],
        adapter_path: [
            "class UpdateShutdownMaintenanceAdapter",
            "Thread(",
            "daemon=True",
            "run_prepare_until_poweroff_ready(",
            "on_poweroff_ready=",
            "def request_poweroff(",
            "request_guest_poweroff()",
        ],
        shutdown_app_path: [
            "def run_prepare_update_shutdown_for_request(",
            "def run_prepare_until_poweroff_ready(",
            "on_poweroff_ready: Callable[[PrepareUpdateShutdownContext], None]",
            "if on_poweroff_ready is not None:",
            "on_poweroff_ready(context)",
            "request_guest_poweroff()",
        ],
    }
    missing = {
        relative(path): [token for token in tokens if token not in texts[path]]
        for path, tokens in required_by_path.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden_by_path = {
        shutdown_app_path: [
            "REQUEST_FILE",
            "RESULT_FILE",
            "request_id_from",
            "request_version_from",
            "write_dispatch_failure_result",
            "def prepare_context(",
            "def write_result(",
            "GuestOperationResult",
            "OperationName.PREPARE_UPDATE_SHUTDOWN",
            "OperationStatus.",
            "PREPARE_UPDATE_SHUTDOWN_REQUEST",
            "PREPARE_UPDATE_SHUTDOWN_RESULT",
            "write_json(",
        ],
        contracts_path: [
            "PREPARE_UPDATE_SHUTDOWN_REQUEST",
            "PREPARE_UPDATE_SHUTDOWN_RESULT",
            (
                'PREPARE_UPDATE_SHUTDOWN = '
                '"tirosh-vitalserver-prepare-update-shutdown.service"'
            ),
        ],
        bootstrap_path: [
            '"tirosh-vitalserver-prepare-update-shutdown.service"',
            '"tirosh-vitalserver-prepare-update-shutdown.path"',
        ],
        collectors_path: [
            "PREPARE_UPDATE_SHUTDOWN_REQUEST",
            "PREPARE_UPDATE_SHUTDOWN_RESULT",
        ],
    }
    forbidden_present = {
        relative(path): [token for token in tokens if token in texts[path]]
        for path, tokens in forbidden_by_path.items()
        if any(token in texts[path] for token in tokens)
    }
    service_file = (
        MACOS_RUNTIME
        / "Support/Guest/systemd/tirosh-vitalserver-prepare-update-shutdown.service"
    )
    if service_file.exists():
        forbidden_present[relative(service_file)] = ["legacy systemd service exists"]
    if missing or forbidden_present:
        return CheckResult(
            "update-shutdown-guest-control-maintenance-api",
            False,
            f"missing={missing} forbidden_present={forbidden_present}",
        )
    return CheckResult(
        "update-shutdown-guest-control-maintenance-api",
        True,
        "update shutdown has a background Guest Control maintenance API",
    )


def check_host_redis_backup_create_uses_guest_control_api() -> CheckResult:
    worker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
        / "MacRuntimeControlCommandWorker.swift"
    )
    gateway_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/GuestControl"
        / "HTTPRuntimeGuestControlGateway.swift"
    )
    usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeServices"
        / "RuntimeGuestMaintenanceControlUseCase.swift"
    )
    worker = read(worker_path)
    gateway = read(gateway_path)
    usecase = read(usecase_path)
    create_body = ""
    marker = "public func createRedisBackup() async throws -> RuntimeCommandResult"
    if marker in worker:
        create_body = worker.split(marker, 1)[1].split(
            "public func createRuntimeDataBackup",
            1,
        )[0]
    required = {
        relative(worker_path): [
            "guestMaintenanceController",
            "controller.createRedisBackup(gateway: gateway)",
            "RuntimeCommandResult(guestControlOperation: operation)",
        ],
        relative(gateway_path): [
            "func createRedisBackup() throws -> RuntimeGuestControlServiceOperation",
            'path: "/v1/maintenance/redis-backup"',
        ],
        relative(usecase_path): [
            "RuntimeGuestMaintenanceControlUseCase",
            "expectedService: \"redis-backup\"",
            "expectedCommand: .redisBackup",
            "operation.command == expectedCommand",
            "operation.service == expectedService",
        ],
    }
    texts = {
        relative(worker_path): worker,
        relative(gateway_path): gateway,
        relative(usecase_path): usecase,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = [
        "ensureExecutable(.launcher)",
        "RuntimeControlClientConstants.RuntimeCommand.redisBackup",
        "RuntimeCommandFactory.shellCommand",
        "runPrivileged",
    ]
    present = [token for token in forbidden if token in create_body]
    if not create_body or missing or present:
        return CheckResult(
            "host-redis-backup-create-guest-control-api",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "host-redis-backup-create-guest-control-api",
        True,
        "Host createRedisBackup consumes Guest Control maintenance API",
    )


def check_host_redis_restore_uses_guest_control_api() -> CheckResult:
    worker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
        / "MacRuntimeControlCommandWorker.swift"
    )
    gateway_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/GuestControl"
        / "HTTPRuntimeGuestControlGateway.swift"
    )
    usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeServices"
        / "RuntimeGuestMaintenanceControlUseCase.swift"
    )
    worker = read(worker_path)
    gateway = read(gateway_path)
    usecase = read(usecase_path)
    marker = "public func restoreRedisBackup(backupURL: URL) async throws"
    restore_body = ""
    if marker in worker:
        restore_body = worker.split(marker, 1)[1].split(
            "public func restoreRuntimeDataBackup",
            1,
        )[0]
    required = {
        relative(worker_path): [
            "controller.restoreRedisBackup(",
            "archive: archive",
            "RuntimeCommandResult(guestControlOperation: operation)",
        ],
        relative(gateway_path): [
            "func restoreRedisBackup(archive: String)",
            'path: "/v1/maintenance/redis-restore"',
        ],
        relative(usecase_path): [
            "restoreRedisBackup(",
            "expectedService: \"redis-restore\"",
            "expectedCommand: .redisRestore",
        ],
    }
    texts = {
        relative(worker_path): worker,
        relative(gateway_path): gateway,
        relative(usecase_path): usecase,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = [
        "ensureExecutable(.launcher)",
        "RuntimeControlClientConstants.RuntimeCommand.redisRestore",
        "RuntimeCommandFactory.shellCommand",
        "runPrivileged",
    ]
    present = [token for token in forbidden if token in restore_body]
    if not restore_body or missing or present:
        return CheckResult(
            "host-redis-restore-guest-control-api",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "host-redis-restore-guest-control-api",
        True,
        "Host restoreRedisBackup consumes Guest Control maintenance API",
    )


def check_host_datastore_repair_uses_guest_control_api() -> CheckResult:
    worker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
        / "MacRuntimeControlCommandWorker.swift"
    )
    gateway_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/GuestControl"
        / "HTTPRuntimeGuestControlGateway.swift"
    )
    usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeServices"
        / "RuntimeGuestMaintenanceControlUseCase.swift"
    )
    guest_api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    guest_usecase_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    worker = read(worker_path)
    gateway = read(gateway_path)
    usecase = read(usecase_path)
    guest_api = read(guest_api_path)
    guest_usecase = read(guest_usecase_path)
    marker = "public func repairDatastore() async throws"
    repair_body = ""
    if marker in worker:
        repair_body = worker.split(marker, 1)[1].split(
            "public func repairVMDisk",
            1,
        )[0]
    required = {
        relative(worker_path): [
            "controller.repairDatastore(gateway: gateway)",
            "RuntimeCommandResult(guestControlOperation: operation)",
        ],
        relative(gateway_path): [
            "func repairDatastore()",
            'path: "/v1/maintenance/datastore-repair"',
        ],
        relative(usecase_path): [
            "repairDatastore(",
            "expectedService: \"datastore-repair\"",
            "expectedCommand: .repairDatastore",
        ],
        relative(guest_api_path): [
            '["v1", "maintenance", "datastore-repair"]',
            "usecases.repair_datastore().as_json()",
        ],
        relative(guest_usecase_path): [
            '"maintenance:datastore-repair:create"',
            "def repair_datastore(",
        ],
    }
    texts = {
        relative(worker_path): worker,
        relative(gateway_path): gateway,
        relative(usecase_path): usecase,
        relative(guest_api_path): guest_api,
        relative(guest_usecase_path): guest_usecase,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = [
        "ensureExecutable(.launcher)",
        "RuntimeControlClientConstants.RuntimeCommand.repairDatastore",
        "RuntimeCommandFactory.shellCommand",
        "runPrivileged",
    ]
    present = [token for token in forbidden if token in repair_body]
    if not repair_body or missing or present:
        return CheckResult(
            "host-datastore-repair-guest-control-api",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "host-datastore-repair-guest-control-api",
        True,
        "Host repairDatastore consumes Guest Control maintenance API",
    )


def check_cli_datastore_repair_uses_guest_control_api() -> CheckResult:
    workflow_actions_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Lifecycle"
        / "RuntimeLifecycle+WorkflowActions.swift"
    )
    composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeDatastoreRepairComposition.swift"
    )
    workflow_path = (
        MACOS_RUNTIME
        / "Sources/Workflow/RuntimeRepairLifecycle"
        / "RuntimeDatastoreRepairWorkflow.swift"
    )
    service_support_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Support"
        / "RuntimeLifecycle+ServiceSupport.swift"
    )
    guest_repair_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/redis_repair.py"
    )
    guest_contracts_path = GUEST_TOOLS / "src/tirosh_guest_tools/contracts.py"
    guest_bootstrap_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/infrastructure/bootstrap_operations.py"
    )
    workflow_actions = read(workflow_actions_path)
    composition = read(composition_path)
    workflow = read(workflow_path)
    service_support = read(service_support_path)
    guest_repair = read(guest_repair_path)
    guest_contracts = read(guest_contracts_path)
    guest_bootstrap = read(guest_bootstrap_path)
    required = {
        relative(workflow_actions_path): [
            "runGuestDatastoreRepair:",
            "repairDatastoreThroughGuestControl()",
        ],
        relative(composition_path): [
            "runGuestDatastoreRepair",
            "RuntimeDatastoreRepairWorkflow().repair",
        ],
        relative(workflow_path): [
            "runGuestDatastoreRepair",
            "datastore repair guest operation completed operationId=",
        ],
        relative(service_support_path): [
            "func repairDatastoreThroughGuestControl()",
            "RuntimeGuestMaintenanceControlUseCase()",
            ".repairDatastore(gateway: gateway)",
        ],
        relative(guest_repair_path): [
            "def run_repair_datastore()",
            "restart_runtime_compose()",
            "def restart_runtime_compose()",
        ],
    }
    texts = {
        relative(workflow_actions_path): workflow_actions,
        relative(composition_path): composition,
        relative(workflow_path): workflow,
        relative(service_support_path): service_support,
        relative(guest_repair_path): guest_repair,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden_tokens = [
        "removeDatastoreRepairResult",
        "writeDatastoreRepairRequest",
        "loadDatastoreRepairResultDocument",
        "removePreviousResult",
        "writeRequest",
        "loadResult",
        "RuntimeDatastoreRepairRequest",
    ]
    forbidden_paths = {
        relative(composition_path): composition,
        relative(workflow_path): workflow,
        relative(guest_repair_path): guest_repair,
        relative(guest_contracts_path): guest_contracts,
        relative(guest_bootstrap_path): guest_bootstrap,
    }
    guest_forbidden_tokens = [
        "REQUEST_FILE",
        "RESULT_FILE",
        "REPAIR_DATASTORE_REQUEST",
        "REPAIR_DATASTORE_RESULT",
        'REPAIR_DATASTORE = "tirosh-vitalserver-repair-datastore.service"',
        '"tirosh-vitalserver-repair-datastore.service"',
        "request_id_from",
        "write_result(",
        "OperationName.REPAIR_DATASTORE",
        "OperationStatus.",
    ]
    forbidden_tokens_by_path = {
        relative(composition_path): forbidden_tokens,
        relative(workflow_path): forbidden_tokens,
        relative(guest_repair_path): guest_forbidden_tokens,
        relative(guest_contracts_path): guest_forbidden_tokens,
        relative(guest_bootstrap_path): guest_forbidden_tokens,
    }
    present = {
        path: [token for token in forbidden_tokens_by_path[path] if token in text]
        for path, text in forbidden_paths.items()
        if any(token in text for token in forbidden_tokens_by_path[path])
    }
    if missing or present:
        return CheckResult(
            "cli-datastore-repair-guest-control-api",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "cli-datastore-repair-guest-control-api",
        True,
        "CLI datastore repair workflow consumes Guest Control maintenance API",
    )


def check_cli_redis_backup_restore_use_guest_control_api() -> CheckResult:
    lifecycle_path = (
        MACOS_RUNTIME / "Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle.swift"
    )
    service_support_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Support"
        / "RuntimeLifecycle+ServiceSupport.swift"
    )
    lifecycle = read(lifecycle_path)
    service_support = read(service_support_path)
    create_body = ""
    create_marker = "func createRedisBackup() throws"
    if create_marker in lifecycle:
        create_body = lifecycle.split(create_marker, 1)[1].split(
            "func createRuntimeDataBackup",
            1,
        )[0]
    restore_body = ""
    restore_marker = "func restoreRedisBackup(_ archive: URL) throws"
    if restore_marker in lifecycle:
        restore_body = lifecycle.split(restore_marker, 1)[1].split(
            "func restoreRuntimeDataBackup",
            1,
        )[0]
    required = {
        relative(lifecycle_path): [
            "createRedisBackupThroughGuestControl()",
            "restoreRedisBackupThroughGuestControl(",
            ".stageRedisArchiveForGuestRestore(archive)",
        ],
        relative(service_support_path): [
            "func createRedisBackupThroughGuestControl()",
            "func restoreRedisBackupThroughGuestControl(",
            "RuntimeGuestMaintenanceControlUseCase()",
            "HTTPRuntimeGuestControlGateway(",
        ],
    }
    texts = {
        relative(lifecycle_path): lifecycle,
        relative(service_support_path): service_support,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden_create = [
        "runtimeRedisBackupComposition().createBackup()",
        "writeRedisBackupRequest",
        "redisBackupCompositionWithoutStatusMutation",
    ]
    forbidden_restore = [
        "runtimeDataBackupComposition().restoreRedisBackup(archive)",
        "writeRedisRestoreRequest",
        "waitForRedisRestoreResult",
    ]
    present = [
        token for token in forbidden_create if token in create_body
    ] + [
        token for token in forbidden_restore if token in restore_body
    ]
    if not create_body or not restore_body or missing or present:
        return CheckResult(
            "cli-redis-backup-restore-guest-control-api",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "cli-redis-backup-restore-guest-control-api",
        True,
        "CLI redis-backup and redis-restore consume Guest Control maintenance API",
    )


def check_runtime_data_backup_uses_guest_control_maintenance_api() -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/RuntimeDataBackupComposition.swift"
    )
    text = read(path)
    forbidden_files = [
        (
            MACOS_RUNTIME
            / "Sources/Application/UseCases/RepairRuntime"
            / "RuntimeRedisBackupUseCase.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence"
            / "RedisBackupResultReader.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared/RedisBackupDocuments.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Hosts/CLI/ProcessBoundary"
            / "RuntimeRedisBackupComposition.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Workflow/RuntimeRepairLifecycle"
            / "RuntimeRedisBackupWorkflow.swift"
        ),
    ]
    required = [
        "lifecycle.createRedisBackupThroughGuestControl()",
        "lifecycle.restoreRedisBackupThroughGuestControl(",
        "operation.result?.archive",
        "operation.result?.restoredArchive",
    ]
    forbidden = [
        "redisBackupCompositionWithoutStatusMutation",
        "RuntimeRedisBackupComposition(",
        "writeRedisBackupRequest",
        "writeRedisRestoreRequest",
        "waitForRedisRestoreResult",
        "loadRedisRestoreResultDocument",
        "restoreRedisArchive(",
    ]
    existing_forbidden_files = [
        relative(file) for file in forbidden_files if file.exists()
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if missing or present or existing_forbidden_files:
        return CheckResult(
            "runtime-data-backup-guest-control-maintenance-api",
            False,
            "missing="
            f"{missing} forbidden_present={present} "
            f"forbidden_files={existing_forbidden_files} path={relative(path)}",
        )
    return CheckResult(
        "runtime-data-backup-guest-control-maintenance-api",
        True,
        "Runtime data backup/restore consumes Guest Control maintenance API",
    )


def check_product_surfaces_do_not_expose_dev_testkit() -> CheckResult:
    missing_paths = [
        MACOS_RUNTIME / "Sources/Adapters/Inbound/RuntimeControlAPI/TestKit",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation/TestKit"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/TestKit"
        ),
        MACOS_RUNTIME / "Sources/Contracts/RuntimeControl/TestKit",
        PWA / "src/pages/testkit",
    ]
    existing = [relative(path) for path in missing_paths if path_has_files(path)]
    scan_roots = [
        MACOS_RUNTIME / "Sources/Adapters/Inbound/RuntimeControlAPI",
        PWA / "src",
        PWA / "vite.config.ts",
        ROOT / "docs/runtime/macos/runtime-control.openapi.json",
    ]
    matches = find_tokens(scan_roots, ["/dev/testkit", "RuntimeTestKit"])
    if existing or matches:
        return CheckResult(
            "product-surfaces-no-dev-testkit",
            False,
            f"existing_paths={existing} matches={matches[:10]}",
        )
    return CheckResult(
        "product-surfaces-no-dev-testkit",
        True,
        "product API/PWA/Swift TestKit surface is absent",
    )


def check_runtime_control_api_exposes_v2_product_surface() -> CheckResult:
    endpoint_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpointRouting.swift"
    )
    read_handler_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlClientAPIReadHandler.swift"
    )
    openapi_path = ROOT / "docs/runtime/macos/runtime-control.openapi.json"
    swift_capabilities_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlModels.swift"
    )
    pwa_client_path = (
        PWA / "src/infrastructure/console-api/runtimeControlApiClient.ts"
    )
    pwa_generated_path = (
        PWA
        / "src/domain/runtime-control/contracts/generated/runtime-control.ts"
    )
    pwa_schema_path = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    pwa_advanced_path = PWA / "src/pages/advanced/AdvancedPage.tsx"
    pwa_lab_page_path = PWA / "src/pages/lab/LabPage.tsx"
    pwa_pages_test_path = PWA / "src/pages/pages.test.tsx"
    openapi_document = json.loads(read(openapi_path))
    capability_schema = (
        openapi_document.get("components", {})
        .get("schemas", {})
        .get("RuntimeControlCapabilities", {})
    )
    capability_properties = set(capability_schema.get("properties", {}))
    capability_required = set(capability_schema.get("required", []))
    capability_contract_issues: list[str] = []
    if capability_schema.get("additionalProperties") is not False:
        capability_contract_issues.append("additionalProperties must be false")
    if capability_properties != capability_required:
        capability_contract_issues.append(
            "required/properties mismatch: "
            f"missing_required={sorted(capability_properties - capability_required)} "
            f"unknown_required={sorted(capability_required - capability_properties)}"
        )
    if "canUseLab" not in capability_required:
        capability_contract_issues.append("canUseLab must be required")
    if (
        "canUseTestTools" in capability_properties
        or "canUseTestTools" in capability_required
    ):
        capability_contract_issues.append("canUseTestTools must not be a capability")
    texts = {
        relative(endpoint_path): read(endpoint_path),
        relative(read_handler_path): read(read_handler_path),
        relative(openapi_path): read(openapi_path),
        relative(swift_capabilities_path): read(swift_capabilities_path),
        relative(pwa_client_path): read(pwa_client_path),
        relative(pwa_generated_path): read(pwa_generated_path),
        relative(pwa_schema_path): read(pwa_schema_path),
        relative(pwa_advanced_path): read(pwa_advanced_path),
        relative(pwa_lab_page_path): read(pwa_lab_page_path),
        relative(pwa_pages_test_path): read(pwa_pages_test_path),
    }
    required = {
        relative(endpoint_path): [
            'path: "/lab/scenarios"',
            'path: "/lab/sessions"',
            'path: "/lab/vital-files/replay"',
            'path: "/runtime/guest/stack/status"',
            'path: "/runtime/guest/services/start"',
            'path: "/runtime/guest/services/stop"',
            'path: "/runtime/guest/services/restart"',
            'path: "/vitaldb/recorders"',
            'path: "/vitaldb/beds"',
            'path: "/vitaldb/relationships"',
        ],
        relative(read_handler_path): [
            "try await client.loadLabScenarios()",
            "try await client.replayLabVitalFile(request)",
            "try await client.guestStackStatus()",
            "try await client.startGuestService(request)",
            "try await client.restartGuestService(request)",
            "client.loadVitalDBRecorders()",
            "client.loadVitalDBRelationships()",
        ],
        relative(openapi_path): [
            '"canUseLab"',
            '"/lab/scenarios"',
            '"/lab/sessions"',
            '"/lab/vital-files/replay"',
            '"/runtime/guest/services"',
            '"/runtime/guest/stack/status"',
            '"/runtime/guest/services/start"',
            '"/runtime/guest/services/stop"',
            '"/runtime/guest/services/restart"',
            '"/vitaldb/recorders"',
            '"/vitaldb/beds"',
            '"/vitaldb/relationships"',
        ],
        relative(pwa_generated_path): [
            "canUseLab: boolean;",
        ],
        relative(swift_capabilities_path): [
            "public var canUseLab: Bool",
            "canUseLab: Bool = true",
            "self.canUseLab = canUseLab",
        ],
        relative(pwa_client_path): [
            '"/lab/scenarios"',
            '"/lab/sessions"',
            '"/lab/vital-files/replay"',
            '"/runtime/guest/stack/status"',
            '"/runtime/guest/services/start"',
            '"/runtime/guest/services/stop"',
            '"/runtime/guest/services/restart"',
            '"/vitaldb/recorders"',
            '"/vitaldb/beds"',
            '"/vitaldb/relationships"',
        ],
        relative(pwa_schema_path): [
            "canUseLab: z.boolean()",
        ],
        relative(pwa_advanced_path): [
            'stackStatus.state !== "loaded"',
            "Guest stack status is",
            "Failed to read Guest services",
        ],
        relative(pwa_lab_page_path): [
            "useRuntimeCapabilities",
            "capabilities.data?.canUseLab",
            "labCapability === true",
        ],
        relative(pwa_pages_test_path): [
            (
                "shows non-loaded Guest stack status without treating it as "
                "an empty service list"
            ),
            (
                "keeps Product Lab visible but disables Lab commands when Lab "
                "capability is unavailable"
            ),
            'state: "failed"',
            "canUseLab: false",
            "Guest stack status is failed.",
            "No Guest services are reported.",
        ],
    }
    forbidden = [
        "/dev/testkit",
        "RuntimeTestKit",
        "MacTestKit",
        "/runtime/services/start",
        "/runtime/services/stop",
        "/runtime/services/restart",
        "canUseTestTools",
    ]
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    matches = [
        f"{path}:{token}"
        for path, text in texts.items()
        for token in forbidden
        if token in text
    ]
    if missing or matches:
        return CheckResult(
            "runtime-control-api-v2-product-surface",
            False,
            f"missing={missing} forbidden={matches[:10]} "
            f"capability_contract_issues={capability_contract_issues}",
        )
    if capability_contract_issues:
        return CheckResult(
            "runtime-control-api-v2-product-surface",
            False,
            f"capability_contract_issues={capability_contract_issues}",
        )
    return CheckResult(
        "runtime-control-api-v2-product-surface",
        True,
        (
            "Runtime Control API and PWA expose Lab, Guest service, and "
            "VitalDB v2 product routes"
        ),
    )


def check_guest_control_lab_boundary_does_not_name_testkit() -> CheckResult:
    scan_roots = [
        (
            GUEST_TOOLS
            / "src/tirosh_guest_tools/application/guest_control"
        ),
        (
            GUEST_TOOLS
            / "src/tirosh_guest_tools/adapters/outbound/product_lab"
        ),
        GUEST_TOOLS / "tests/test_guest_control_usecases.py",
        GUEST_TOOLS / "tests/test_product_lab_service_adapter.py",
        ROOT / "apps/vitalserver-lab/vitalserver_lab",
        ROOT / "apps/vitalserver-lab/tests",
    ]
    matches = find_tokens(
        scan_roots,
        ["TestKit", "testKit", "testkit", "/dev/testkit", "RuntimeTestKit"],
    )
    if matches:
        return CheckResult(
            "guest-control-lab-boundary-no-testkit",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "guest-control-lab-boundary-no-testkit",
        True,
        "Guest Control Product Lab boundary does not name TestKit",
    )


def check_guest_control_default_state_is_postgres_backed() -> CheckResult:
    api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    runtime_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/runtime.py"
    )
    usecase_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    operation_repository_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/postgres/operation_repository.py"
    )
    vitaldb_repository_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/postgres"
        / "vitaldb_read_model_repository.py"
    )
    api_tests_path = GUEST_TOOLS / "tests/test_guest_control_api.py"
    usecase_tests_path = GUEST_TOOLS / "tests/test_guest_control_usecases.py"
    lab_settings_path = ROOT / "apps/vitalserver-lab/vitalserver_lab/settings.py"
    lab_server_path = ROOT / "apps/vitalserver-lab/vitalserver_lab/server.py"
    lab_postgres_store_path = (
        ROOT / "apps/vitalserver-lab/vitalserver_lab/postgres_store.py"
    )
    lab_tests_path = ROOT / "apps/vitalserver-lab/tests/test_server.py"
    lab_readme_path = ROOT / "apps/vitalserver-lab/README.md"
    compose_path = MACOS_RUNTIME / "Support/Guest/compose.yaml"
    api_text = read(api_path)
    runtime_text = read(runtime_path)
    usecase_text = read(usecase_path)
    operation_repository_text = read(operation_repository_path)
    vitaldb_repository_text = read(vitaldb_repository_path)
    api_tests_text = read(api_tests_path)
    usecase_tests_text = read(usecase_tests_path)
    lab_settings_text = read(lab_settings_path)
    lab_server_text = read(lab_server_path)
    lab_postgres_store_text = read(lab_postgres_store_path)
    lab_tests_text = read(lab_tests_path)
    lab_readme_text = read(lab_readme_path)
    compose_text = read(compose_path)
    required = {
        relative(api_path): [
            "PostgresOperationRepository",
            "PostgresVitalDBReadModelRepository",
            "operations.ensure_schema()",
            "vitaldb_read_model.ensure_schema()",
            "operations=operations",
            "vitaldb_read_model=vitaldb_read_model",
            "usecases.readiness()",
            "HTTPStatus.SERVICE_UNAVAILABLE",
        ],
        relative(usecase_path): [
            "def readiness(self) -> dict[str, object]:",
            "self._operations.check_ready",
            "self._vitaldb_read_model.check_ready",
            '"operationRepository"',
            '"vitaldbReadModel"',
        ],
        relative(operation_repository_path): [
            "def check_ready(self) -> None:",
            '"SELECT 1;"',
            '"guest control operation repository readiness"',
        ],
        relative(vitaldb_repository_path): [
            "def check_ready(self) -> None:",
            '"SELECT 1;"',
            '"vitaldb read model readiness"',
        ],
        relative(api_tests_path): [
            "test_ready_route_reports_postgres_dependency_failure",
            "HTTPStatus.SERVICE_UNAVAILABLE",
            "postgresCommandFailed",
        ],
        relative(usecase_tests_path): [
            "test_readiness_preserves_postgres_operation_repository_failure",
            "postgresCommandFailed",
        ],
        relative(compose_path): [
            "  postgres:",
            "postgres:16-alpine",
            "postgres-data:/var/lib/postgresql/data",
            "  lab:",
            'VITALSERVER_LAB_SESSION_STORE: "postgres"',
            "VITALSERVER_LAB_DATABASE_URL:",
            "  postgres-data:",
        ],
        relative(lab_settings_path): [
            "class LabSettingsConfigurationError(Exception):",
            "def int_from_env(name: str, *, default: int) -> int:",
            "labSettingsInvalidInteger",
            'session_store=os.environ.get("VITALSERVER_LAB_SESSION_STORE", "postgres")',
            'allow_memory_store=bool_from_env("VITALSERVER_LAB_ALLOW_MEMORY_STORE")',
        ],
        relative(lab_server_path): [
            'if settings.session_store == "memory":',
            "if not settings.allow_memory_store:",
            "VITALSERVER_LAB_ALLOW_MEMORY_STORE",
            "labSessionStoreConfigurationInvalid",
        ],
        relative(lab_postgres_store_path): [
            "except OSError as error:",
            "postgresCommandUnavailable",
            "postgres command could not start during",
        ],
        relative(lab_tests_path): [
            "test_memory_session_store_requires_explicit_dev_override",
            "test_load_settings_reports_invalid_port_configuration",
            "test_load_settings_reports_non_positive_port_configuration",
            "test_postgres_store_reports_psql_command_start_failure",
            "LabSettingsConfigurationError",
            "postgresCommandUnavailable",
            "allow_memory_store=False",
            "VITALSERVER_LAB_ALLOW_MEMORY_STORE",
        ],
        relative(lab_readme_path): [
            "Runtime v2 product service",
            "Guest Control `/v1/lab/*`",
            "Runtime Control `/lab/*`",
            "must not call a TestKit container",
            "`/dev/testkit` product route",
            "Postgres-backed session/read-model state",
            "VITALSERVER_LAB_SESSION_STORE=postgres",
            "VITALSERVER_LAB_ALLOW_MEMORY_STORE",
        ],
    }
    texts = {
        relative(api_path): api_text,
        relative(compose_path): compose_text,
        relative(usecase_path): usecase_text,
        relative(operation_repository_path): operation_repository_text,
        relative(vitaldb_repository_path): vitaldb_repository_text,
        relative(api_tests_path): api_tests_text,
        relative(usecase_tests_path): usecase_tests_text,
        relative(lab_settings_path): lab_settings_text,
        relative(lab_server_path): lab_server_text,
        relative(lab_postgres_store_path): lab_postgres_store_text,
        relative(lab_tests_path): lab_tests_text,
        relative(lab_readme_path): lab_readme_text,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = [
        "VolatileOperationRepository",
        "Temporary operation store",
    ]
    present = [
        f"{relative(runtime_path)}:{token}"
        for token in forbidden
        if token in runtime_text
    ]
    if "VITALSERVER_LAB_ALLOW_MEMORY_STORE" in compose_text:
        present.append(
            f"{relative(compose_path)}:VITALSERVER_LAB_ALLOW_MEMORY_STORE"
        )
    if missing or present:
        return CheckResult(
            "guest-control-default-state-postgres-backed",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "guest-control-default-state-postgres-backed",
        True,
        "Guest Control API defaults to Postgres-backed operation/read-model "
        "state and compose includes postgres-backed Lab",
    )


def check_guest_service_operations_persist_status_snapshots() -> CheckResult:
    usecases_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    tests_path = GUEST_TOOLS / "tests/test_guest_control_usecases.py"
    api_tests_path = GUEST_TOOLS / "tests/test_guest_control_api.py"
    usecases_text = read(usecases_path)
    tests_text = read(tests_path)
    api_tests_text = read(api_tests_path)
    required = {
        relative(usecases_path): [
            "self._save_operation_status_snapshot(service=service, command=command)",
            "def _save_operation_status_snapshot(",
            "self._service_control.get_service_status(service)",
            "self._service_control.get_stack_status()",
            "self._operations.save_service_status_snapshot(service_status)",
        ],
        relative(tests_path): [
            "test_restart_service_status_snapshot_failure_is_persisted_as_failed_operation",
            (
                "assert [status.service for status in operations.status_snapshots] "
                "== [\"app\"]"
            ),
            "assert operations.status_snapshots == []",
        ],
        relative(api_tests_path): [
            "test_restart_route_preserves_failed_operation_document",
            "FakeServiceControl(fail_command=\"restart\")",
            '"state"] == "failed"',
            '"kind": "guest-compose-command-failed"',
        ],
    }
    texts = {
        relative(usecases_path): usecases_text,
        relative(tests_path): tests_text,
        relative(api_tests_path): api_tests_text,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    if missing:
        return CheckResult(
            "guest-service-operations-persist-status-snapshots",
            False,
            f"missing={missing}",
        )
    return CheckResult(
        "guest-service-operations-persist-status-snapshots",
        True,
        "Guest service operations persist explicit service status snapshots "
        "through the operation repository after successful commands",
    )


def check_guest_service_control_is_controller_owned_resource() -> CheckResult:
    models_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/domain/guest_control/models.py"
    )
    policy_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/domain/guest_control"
        / "service_reconcile_policy.py"
    )
    usecases_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    repository_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/postgres"
        / "operation_repository.py"
    )
    api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    tests_path = GUEST_TOOLS / "tests/test_guest_control_usecases.py"
    policy_tests_path = (
        GUEST_TOOLS / "tests/test_guest_service_reconcile_policy.py"
    )
    required = {
        relative(models_path): [
            "class GuestServiceDesiredState",
            "class GuestServiceSpec",
            "class GuestServiceStatusRead",
            "class GuestServiceCondition",
            "class GuestServiceResource",
        ],
        relative(policy_path): [
            "def reconcile_guest_service(",
            "GuestServiceReconcileDecision",
            "GuestServiceReconcileEffect",
            "GuestServiceObservedState",
            "requested_command == ServiceCommand.RESTART",
        ],
        relative(usecases_path): [
            "def get_guest_service_resource(",
            "def observe_guest_service(",
            "def update_guest_service_spec(",
            "def reconcile_guest_service(",
            "self._save_guest_service_spec(",
            "reconcile_guest_service(",
            "_guest_service_observed_state(",
            "self._operations.save_guest_service_resource(resource)",
        ],
        relative(repository_path): [
            "CREATE TABLE IF NOT EXISTS guest_service_resources",
            "def save_guest_service_resource(",
            "def get_guest_service_resource(",
            "guest_service_resource_from_json",
        ],
        relative(api_path): [
            'parts[3] == "resource"',
            'parts[3] == "spec"',
            'parts[3] == "observe"',
            'parts[3] == "reconcile"',
            "def do_PUT(self) -> None:",
        ],
        relative(tests_path): [
            "test_guest_service_resource_get_is_side_effect_free",
            "test_observe_guest_service_reads_and_persists_loaded_status",
            "test_guest_service_controller_rejects_unknown_service",
            "test_guest_service_spec_update_rejects_invalid_desired_state",
            "test_guest_service_spec_update_persists_desired_state",
            "test_reconcile_guest_service_without_spec_is_blocked",
        ],
        relative(policy_tests_path): [
            "test_reconcile_blocks_missing_spec",
            "test_reconcile_blocks_failed_status_read",
            "test_reconcile_noops_when_desired_running_is_observed",
            "test_reconcile_restarts_when_restart_is_requested",
        ],
    }
    texts = {path: read(ROOT / path) for path in required}
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = {
        relative(policy_path): [
            "compose",
            "subprocess",
            "Postgres",
            "open(",
            "Path(",
        ],
    }
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    if missing or present:
        return CheckResult(
            "guest-service-control-controller-owned-resource",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "guest-service-control-controller-owned-resource",
        True,
        "Guest service control exposes resource/spec/observe/reconcile contracts, "
        "stores explicit resource state in Postgres, and keeps reconcile policy pure",
    )


def check_runtime_config_does_not_enable_testkit() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Support/Guest/runtime-config.json",
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared/GuestRuntimeConfigDocument.swift"
        ),
        GUEST_TOOLS / "src/tirosh_guest_tools/domain/runtime_config.py",
    ]
    matches = find_tokens(paths, ["testkitEnabled", "testkit_enabled"])
    if matches:
        return CheckResult(
            "runtime-config-no-testkit-enabled",
            False,
            f"matches={matches}",
        )
    return CheckResult(
        "runtime-config-no-testkit-enabled",
        True,
        "runtime config does not carry TestKit enablement",
    )


def check_product_packaging_uses_lab_not_testkit() -> CheckResult:
    paths = [
        ROOT / "config/vm-build.toml",
        MACOS_RUNTIME / "Support/Guest/compose.yaml",
        MACOS_RUNTIME / "release.json",
        MACOS_RUNTIME / "release-dev.json",
        ROOT / "apps/vitalserver-lab/Dockerfile",
        (
            ROOT
            / "packages/vitalserver-devtools/src/tirosh_vitalserver"
            / "devtools/config/release_manifest.py"
        ),
        (
            ROOT
            / "packages/vitalserver-devtools/src/tirosh_vitalserver"
            / "devtools/application/usecases/macos_package.py"
        ),
    ]
    texts = {relative(path): read(path) for path in paths}
    required = {
        "config/vm-build.toml": [
            'lab_image = "vitalserver-lab:',
            'lab_dockerfile = "apps/vitalserver-lab/Dockerfile"',
            '"apps/vitalserver-lab"',
        ],
        "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml": [
            "  lab:",
            "image: vitalserver-lab:",
            "VITALSERVER_LAB_SESSION_STORE:",
            "VITALSERVER_LAB_DATABASE_URL:",
            "VITALSERVER_LAB_VITAL_FILES_MOUNT:",
        ],
        "apps/vitalserver-macos-runtime/release.json": [
            '"lab"',
            '"image": "vitalserver-lab:',
            '"postgres"',
            '"image": "postgres:',
        ],
        "apps/vitalserver-macos-runtime/release-dev.json": [
            '"lab"',
            '"image": "vitalserver-lab:',
            '"postgres"',
            '"image": "postgres:',
        ],
        "apps/vitalserver-lab/Dockerfile": [
            "RUN apk add --no-cache postgresql-client",
            "VITALSERVER_LAB_VITAL_FILES_MOUNT=/mnt/tirosh-vital-files",
        ],
        (
            "packages/vitalserver-devtools/src/tirosh_vitalserver"
            "/devtools/config/release_manifest.py"
        ): [
            'required_service_string(release, "lab", "image")',
            'required_service_string(release, "postgres", "image")',
            "Lab is the product service",
        ],
        (
            "packages/vitalserver-devtools/src/tirosh_vitalserver"
            "/devtools/application/usecases/macos_package.py"
        ): [
            "REQUIRED_RUNTIME_PRODUCT_COMPOSE_SERVICES",
            '"postgres"',
            '"lab"',
            '"edge"',
            '"guest-compose-product-services"',
            'service == "testkit"',
        ],
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = [
        "testkit",
        "TestKit",
        "vitalserver-testkit",
        "packages/vitalserver-testkit",
        "tirosh-vitalserver-testkit",
    ]
    forbidden_scan_texts = {
        path: text
        for path, text in texts.items()
        if "/devtools/" not in path
    }
    present = {
        path: [token for token in forbidden if token in text]
        for path, text in forbidden_scan_texts.items()
        if any(token in text for token in forbidden)
    }
    if missing or present:
        return CheckResult(
            "product-packaging-lab-not-testkit",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "product-packaging-lab-not-testkit",
        True,
        "product packaging includes Lab and excludes TestKit runtime artifacts",
    )


def check_runtime_control_client_does_not_expose_whole_stack_start_stop(
) -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeClientContracts.swift"
    )
    text = read(path)
    forbidden = [
        "func startRuntimeServices() async throws -> RuntimeCommandResult",
        "func stopRuntimeServices() async throws -> RuntimeCommandResult",
        "func repairProxy() async throws -> RuntimeCommandResult",
        "func repairDatastore() async throws -> RuntimeCommandResult",
        "func repairVMDisk() async throws -> RuntimeCommandResult",
        "func repairRuntimeServices() async throws -> RuntimeCommandResult",
        "func createRedisBackup() async throws -> RuntimeCommandResult",
    ]
    runtime_control_protocol = text.split("public extension RuntimeControlClient", 1)[0]
    host_client_protocol = text.split("public protocol RuntimeHostClient", 1)[-1]
    present = [token for token in forbidden if token in runtime_control_protocol]
    host_required = [
        "func repairProxy() async throws -> RuntimeCommandResult",
        "func repairDatastore() async throws -> RuntimeCommandResult",
        "func repairVMDisk() async throws -> RuntimeCommandResult",
        "func repairRuntimeServices() async throws -> RuntimeCommandResult",
        "func createRedisBackup() async throws -> RuntimeCommandResult",
    ]
    missing_host = [
        token for token in host_required if token not in host_client_protocol
    ]
    if present or missing_host:
        return CheckResult(
            "runtime-control-client-no-whole-stack-start-stop",
            False,
            (
                f"forbidden_present={present} missing_host={missing_host} "
                f"path={relative(path)}"
            ),
        )

    product_caller_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
            / "RuntimeControlClientAPIReadHandler.swift"
        ),
    ]
    product_client_calls = [
        "controlClient.repairProxy()",
        "controlClient.repairDatastore()",
        "controlClient.repairVMDisk()",
        "controlClient.repairRuntimeServices()",
        "controlClient.createRedisBackup()",
        "client.repairProxy()",
        "client.repairDatastore()",
        "client.repairVMDisk()",
        "client.repairRuntimeServices()",
        "client.createRedisBackup()",
    ]
    matches = find_tokens(product_caller_paths, product_client_calls)
    if matches:
        return CheckResult(
            "runtime-control-client-no-whole-stack-start-stop",
            False,
            f"maintenance_calls_on_product_client={matches[:10]}",
        )
    return CheckResult(
        "runtime-control-client-no-whole-stack-start-stop",
        True,
        (
            "RuntimeControlClient consumes product operations; Host maintenance "
            "commands stay on RuntimeHostClient"
        ),
    )


def check_runtime_control_http_does_not_expose_whole_stack_start_stop(
) -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Adapters/Inbound/RuntimeControlAPI",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels"
            / "RuntimeViewModel.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Views"
        ),
        PWA / "src",
        ROOT / "docs/runtime/macos/runtime-control.openapi.json",
        ROOT / "docs/pwa/parity.md",
    ]
    forbidden = [
        "/runtime/services/start",
        "/runtime/services/stop",
        "startRuntimeServices",
        "stopRuntimeServices",
        "useStartRuntimeServices",
        "useStopRuntimeServices",
        "Start Runtime Services",
        "Stop Runtime Services",
        "showingStartServicesConfirmation",
        "showingStopServicesConfirmation",
        "viewModel.startRuntimeServices()",
        "viewModel.stopRuntimeServices()",
        "controlClient.startRuntimeServices()",
        "controlClient.stopRuntimeServices()",
        "AppConstants.Actions.startRuntimeServices",
        "AppConstants.Actions.stopRuntimeServices",
        "Start services",
        "Stop services",
    ]
    matches = find_tokens(paths, forbidden)
    if matches:
        return CheckResult(
            "runtime-control-http-no-whole-stack-start-stop",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-control-http-no-whole-stack-start-stop",
        True,
        "whole-stack service start/stop is native Host maintenance only",
    )


def check_host_runtime_service_control_is_host_only() -> CheckResult:
    managed_service_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeManagedService.swift"
    )
    service_control_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeServices"
        / "ControlRuntimeServicesUseCase.swift"
    )
    managed_service_text = read(managed_service_path)
    service_control_text = read(service_control_path)
    forbidden_guest_services = [
        "case app",
        "case postgres",
        "case redis",
        "case lab",
        "case recorderIngress",
        "case vitalDBObserver",
        "case swaggerUI",
        "case redisUI",
        "case testkit",
        '"app"',
        '"postgres"',
        '"redis"',
        '"lab"',
        '"recorder-ingress"',
        '"vitaldb-observer"',
        '"swagger-ui"',
        '"redis-ui"',
        '"testkit"',
        '"compose"',
    ]
    matches = [
        token for token in forbidden_guest_services if token in managed_service_text
    ]
    required_messages = [
        "host runtime services repair requested",
        "host runtime services repaired",
        "host runtime services start requested",
        "host runtime services started",
        "host runtime services stop requested",
        "host runtime services stopped",
    ]
    missing_messages = [
        token for token in required_messages if token not in service_control_text
    ]
    if matches or missing_messages:
        return CheckResult(
            "host-runtime-service-control-host-only",
            False,
            (
                f"guest_service_tokens={matches} "
                f"missing_host_messages={missing_messages}"
            ),
        )
    return CheckResult(
        "host-runtime-service-control-host-only",
        True,
        (
            "Host runtime service control is limited to Host launchd services "
            "and labels itself as Host-owned"
        ),
    )


def check_swift_product_ui_does_not_expose_whole_stack_start_stop(
) -> CheckResult:
    paths = [
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation"
        ),
    ]
    forbidden = [
        "showingStartServicesConfirmation",
        "showingStopServicesConfirmation",
        "func startRuntimeServices() async",
        "func stopRuntimeServices() async",
        "AppConstants.Actions.startRuntimeServices",
        "AppConstants.Actions.stopRuntimeServices",
        "public static let startRuntimeServices",
        "public static let stopRuntimeServices",
        "startRuntimeServicesConfirmation",
        "stopRuntimeServicesConfirmation",
        "runtimeServiceControlHelp",
        "runtimeServicesStartPreparing",
        "runtimeServicesStopPreparing",
    ]
    matches = find_tokens(paths, forbidden)
    if matches:
        return CheckResult(
            "swift-product-ui-no-whole-stack-start-stop",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "swift-product-ui-no-whole-stack-start-stop",
        True,
        (
            "Swift product UI exposes Guest service controls instead of "
            "whole-stack start/stop"
        ),
    )


def check_swift_product_lab_commands_require_lab_capability() -> CheckResult:
    view_model_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels"
        / "RuntimeViewModel+Lab.swift"
    )
    panel_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Lab"
        / "RuntimeLabPanel.swift"
    )
    test_path = (
        MACOS_RUNTIME
        / "Tests/MacControlPanelHostTests/RuntimeViewModelCapabilityTests.swift"
    )
    texts = {
        relative(view_model_path): read(view_model_path),
        relative(panel_path): read(panel_path),
        relative(test_path): read(test_path),
    }
    required = {
        relative(view_model_path): [
            "var labCanUseProductLab: Bool",
            "capabilities.canUseLab",
            "var labCanReplayVitalFile: Bool",
            "guard labCanUseProductLab else",
            "RuntimeLabPanelText.labCapabilityUnavailable",
        ],
        relative(panel_path): [
            ".disabled(!viewModel.labCanCreateSession)",
            ".disabled(!viewModel.labCanControlSelectedSession)",
            ".disabled(!viewModel.labCanReplayVitalFile)",
        ],
        relative(test_path): [
            "testProductLabCommandsAreBlockedWhenLabCapabilityIsUnavailable",
            "RuntimeControlCapabilities(canUseLab: false)",
            "XCTAssertEqual(client.labCreateRequests, [])",
            "XCTAssertEqual(client.labReplayRequests, [])",
        ],
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    if missing:
        return CheckResult(
            "swift-product-lab-command-capability",
            False,
            f"missing={missing}",
        )
    return CheckResult(
        "swift-product-lab-command-capability",
        True,
        "Swift Product Lab command affordances require canUseLab",
    )


def check_swift_event_display_does_not_promote_container_observation(
) -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies"
        / "RuntimeEventDisplayPolicy.swift"
    )
    text = read(path)
    forbidden = [
        "event.containerObservation",
        "containerObservation?.recorderIngressStatus",
        "activeRecorderConnectionsLabel",
        "knownRecordersLabel",
    ]
    present = [token for token in forbidden if token in text]
    if present:
        return CheckResult(
            "swift-event-display-no-container-observation-promotion",
            False,
            f"forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "swift-event-display-no-container-observation-promotion",
        True,
        (
            "Swift event display does not promote container diagnostics "
            "into product recorder details"
        ),
    )


def check_swift_guest_readiness_presentation_does_not_use_runtime_state(
) -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies"
        / "RuntimeStatusGuestReadinessPresentationPolicy.swift"
    )
    text = read(path)
    forbidden = [
        "guestRuntimeStateStale",
        "runtimeStateStale",
        "runtimeStateMissing",
    ]
    present = [token for token in forbidden if token in text]
    if present:
        return CheckResult(
            "swift-guest-readiness-presentation-no-runtime-state",
            False,
            f"forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "swift-guest-readiness-presentation-no-runtime-state",
        True,
        "Swift Guest readiness presentation does not use runtime-state "
        "stale/missing signals",
    )


def check_guest_service_control_has_separate_capability() -> CheckResult:
    required_paths = [
        MACOS_RUNTIME / "Sources/Contracts/RuntimeControl/RuntimeControlModels.swift",
        PWA / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts",
        PWA / "src/domain/runtime-control/contracts/generated/runtime-control.ts",
        ROOT / "docs/runtime/macos/runtime-control.openapi.json",
        PWA / "src/pages/advanced/AdvancedPage.tsx",
    ]
    missing = [
        relative(path)
        for path in required_paths
        if "canControlGuestServices" not in read(path)
    ]
    advanced = read(PWA / "src/pages/advanced/AdvancedPage.tsx")
    forbidden = "capabilities.data?.canControlRuntimeServices === true"
    if missing or forbidden in advanced:
        return CheckResult(
            "guest-service-control-separate-capability",
            False,
            (
                f"missing={missing} "
                f"advanced_uses_runtime_capability={forbidden in advanced}"
            ),
        )
    return CheckResult(
        "guest-service-control-separate-capability",
        True,
        (
            "Guest service controls use canControlGuestServices, not Host runtime "
            "maintenance capability"
        ),
    )


def check_guest_capability_checks_use_guest_control_api() -> CheckResult:
    usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/UpdateRuntime"
        / "RequireRuntimeGuestCapabilityUseCase.swift"
    )
    composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeGuestCapabilityCheckerComposition.swift"
    )
    gateway_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/GuestControl"
        / "HTTPRuntimeGuestControlGateway.swift"
    )
    guest_api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    guest_usecases_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    requirement_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared"
        / "RuntimeGuestCapabilityRequirement.swift"
    )
    texts = {
        relative(usecase_path): read(usecase_path),
        relative(composition_path): read(composition_path),
        relative(gateway_path): read(gateway_path),
        relative(guest_api_path): read(guest_api_path),
        relative(guest_usecases_path): read(guest_usecases_path),
        relative(requirement_path): read(requirement_path),
    }
    required = {
        relative(usecase_path): [
            "RuntimeGuestCapabilityReadResult",
            "loadCapabilities",
            ".capabilitiesReadFailed(",
        ],
        relative(composition_path): [
            "guestControlGateway.capabilities()",
        ],
        relative(gateway_path): [
            "func capabilities() throws -> RuntimeGuestControlCapabilities",
            'path: "/v1/capabilities"',
        ],
        relative(guest_api_path): [
            "return HTTPStatus.OK, usecases.capabilities()",
        ],
        relative(guest_usecases_path): [
            "def capabilities(self) -> dict[str, object]:",
            "if self._product_lab is not None:",
            "if self._vitaldb_read_model is not None:",
            "if self._redis_backup is not None:",
            "if self._update_shutdown is not None:",
        ],
        relative(requirement_path): [
            "guestControlCapability",
            "maintenance:update-shutdown:create",
            "maintenance:update-activation:create",
            "maintenance:redis-backup:create",
            "maintenance:redis-restore:create",
            "maintenance:datastore-repair:create",
        ],
    }
    forbidden = [
        "loadRuntimeState",
        "RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>",
        "GuestRuntimeCapabilities",
        "runtimeStateReadFailed",
        "missingRuntimeState",
    ]
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    matches = [
        f"{path}:{token}"
        for path, text in texts.items()
        for token in forbidden
        if token in text
    ]
    if missing or matches:
        return CheckResult(
            "guest-capability-checks-guest-control-api",
            False,
            f"missing={missing} forbidden={matches[:10]}",
        )
    return CheckResult(
        "guest-capability-checks-guest-control-api",
        True,
        "Guest capability checks consume Guest Control /v1/capabilities",
    )


def check_cli_consumes_guest_control_product_apis() -> CheckResult:
    command_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/CLI/Commands/RuntimeLifecycleCommand.swift"
    )
    lifecycle_path = (
        MACOS_RUNTIME / "Sources/Hosts/CLI/ProcessBoundary/RuntimeLifecycle.swift"
    )
    gateway_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/GuestControl"
        / "HTTPRuntimeGuestControlGateway.swift"
    )
    texts = {
        relative(command_path): read(command_path),
        relative(lifecycle_path): read(lifecycle_path),
        relative(gateway_path): read(gateway_path),
    }
    required = {
        relative(command_path): [
            '"guest-stack-status"',
            '"guest-service-start"',
            '"guest-service-stop"',
            '"guest-service-restart"',
            '"vitaldb-observation"',
            '"vitaldb-recorders"',
            '"vitaldb-recorder-activity"',
            '"vitaldb-beds"',
            '"vitaldb-relationships"',
            '"lab-scenarios"',
            '"lab-beds"',
            '"lab-recorders"',
            '"lab-session-create"',
            '"lab-session-get"',
            '"lab-session-start"',
            '"lab-session-stop"',
            '"lab-vital-replay"',
        ],
        relative(lifecycle_path): [
            "HTTPRuntimeGuestControlGateway(",
            "RuntimeGuestProductServiceControlUseCase()",
            "gateway.stackStatus()",
            "gateway.labScenarios()",
            "gateway.replayLabVitalFile(request)",
            "gateway.latestVitalDBObservation()",
            "gateway.vitalDBRelationships()",
        ],
        relative(gateway_path): [
            'path: "/v1/services"',
            'path: "/v1/stack/status"',
            'path: "/v1/vitaldb/observations/latest"',
            'path: "/v1/vitaldb/relationships"',
            'path: "/v1/lab/scenarios"',
            'path: "/v1/lab/vital-files/replay"',
        ],
    }
    forbidden = [
        "testkit-start",
        "testkit-stop",
        "testkit-restart",
        "/dev/testkit",
        "RuntimeTestKit",
        "MacTestKit",
        "JSONFileRuntimeGuestGateway",
        "RuntimeGuestRequests",
    ]
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    matches = [
        f"{path}:{token}"
        for path, text in texts.items()
        for token in forbidden
        if token in text
    ]
    if missing or matches:
        return CheckResult(
            "cli-guest-product-apis",
            False,
            f"missing={missing} forbidden={matches[:10]}",
        )
    return CheckResult(
        "cli-guest-product-apis",
        True,
        "CLI consumes Guest Control service, Lab, and VitalDB product APIs",
    )


def check_product_readmes_do_not_promote_legacy_sources() -> CheckResult:
    readme_paths = [
        ROOT / "README.md",
        MACOS_RUNTIME / "README.md",
        PWA / "README.md",
    ]
    forbidden = {
        relative(ROOT / "README.md"): [
            "vitalserver-testkit/        productization smoke",
            "bounded productization smoke scenario",
            "Host runtime이 process, filesystem, update, recovery state",
            "Compose는 제품 실행 방식이 아니라",
        ],
        relative(MACOS_RUNTIME / "README.md"): [
            "source of truth는 watchdog/runtime",
            "runtime-observability.sqlite`입니다. UI와 Runtime",
            "guest runtime-state.json\n  -> watchdog/runtime",
            "../../docs/macos-runtime/",
        ],
        relative(PWA / "README.md"): [
            "/dev/testkit",
        ],
    }
    texts = {relative(path): read(path) for path in readme_paths}
    matches = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    root_readme = texts[relative(ROOT / "README.md")]
    root_required = [
        "Guest/Container runtime은 product service control",
        "vitalserver-lab/            Product Lab",
        "vitalserver-testkit/        dev/load-test",
        "make testkit/smoke        # bounded dev verification smoke scenario",
    ]
    missing = [token for token in root_required if token not in root_readme]
    if matches or missing:
        return CheckResult(
            "product-readmes-no-legacy-sources",
            False,
            f"matches={matches} missing={missing}",
        )
    return CheckResult(
        "product-readmes-no-legacy-sources",
        True,
        "product READMEs describe Guest/Postgres and Lab v2 sources",
    )


def check_testkit_package_is_dev_tooling_only() -> CheckResult:
    testkit_pyproject_path = ROOT / "packages/vitalserver-testkit/pyproject.toml"
    testkit_readme_path = ROOT / "packages/vitalserver-testkit/README.md"
    testkit_usage_path = ROOT / "docs/testkit/usage.md"
    repository_map_path = ROOT / "site-docs/dev/repository-map.md"
    testkit_pyproject = read(testkit_pyproject_path)
    testkit_readme = read(testkit_readme_path)
    testkit_usage = read(testkit_usage_path)
    repository_map = read(repository_map_path)

    missing: list[str] = []
    required_description = "Dev-only smoke/load tooling"
    if required_description not in testkit_pyproject:
        missing.append(required_description)
    required_readme = [
        "dev-only smoke/load",
        "product runtime stack에 포함되면 안 됩니다",
        "apps/vitalserver-lab",
        "Guest Control `/v1/lab/*`",
        "product-facing\nruntime 기능으로 다시 노출하지 않습니다",
    ]
    missing.extend(
        token for token in required_readme if token not in testkit_readme
    )
    required_usage = [
        "Runtime v2에서는 TestKit이 제품 runtime surface가 아닙니다",
        "make testkit/smoke",
        "make testkit/verify",
        "make testkit/load",
        "make testkit/stream",
    ]
    missing.extend(token for token in required_usage if token not in testkit_usage)
    required_repository_map = [
        "dev-only simulated recorder와 smoke/load 검증 도구 경계를 유지",
    ]
    missing.extend(
        token for token in required_repository_map if token not in repository_map
    )
    forbidden = [
        "make testkit-smoke",
        "make testkit-verify",
        "make testkit-load",
        "make testkit-stream",
        "product-facing QA 기능",
        "Test 탭은 Runtime Control browser console과 Testkit API 상태를 확인",
        "Testkit API를 product-facing",
    ]
    matches = []
    documents = {
        "packages/vitalserver-testkit/README.md": testkit_readme,
        "docs/testkit/usage.md": testkit_usage,
        "site-docs/dev/repository-map.md": repository_map,
    }
    for document_name, content in documents.items():
        matches.extend(
            f"{document_name}:{token}" for token in forbidden if token in content
        )
    if missing or matches:
        return CheckResult(
            "testkit-package-dev-tooling-only",
            False,
            f"missing={missing} matches={matches}",
        )
    return CheckResult(
        "testkit-package-dev-tooling-only",
        True,
        "vitalserver-testkit is classified as dev-only smoke/load tooling, "
        "not a product runtime service or product API boundary",
    )


def check_runtime_proof_local_artifacts_and_private_samples_are_ignored(
) -> CheckResult:
    gitignore_path = ROOT / ".gitignore"
    dockerignore_path = ROOT / ".dockerignore"
    testkit_usage_path = ROOT / "docs/testkit/usage.md"
    gitignore = read(gitignore_path)
    dockerignore = read(dockerignore_path)
    testkit_usage = read(testkit_usage_path)

    required_ignored = [
        "*.vital",
        "data/",
        "packages/vitalserver-testkit/src/tirosh_vitalserver/testkit/fixtures/",
        "apps/vitalserver-macos-runtime/.build-runtime-check/",
    ]
    required_docker_only = [
        "apps/vitalserver-lab/tests/",
    ]
    required_docs = [
        "실제 recorder sample은 환자 정보가 섞일 수 있으므로",
        "TestKit package와 remote branch 최종 결과에 포함하지 않습니다",
        "TestKit은 `data/`를 자동 탐색하지 않습니다",
    ]
    missing = [
        f".gitignore:{token}"
        for token in required_ignored
        if token not in gitignore
    ] + [
        f".dockerignore:{token}"
        for token in [*required_ignored, *required_docker_only]
        if token not in dockerignore
    ] + [
        f"docs/testkit/usage.md:{token}"
        for token in required_docs
        if token not in testkit_usage
    ]
    if missing:
        return CheckResult(
            "runtime-proof-local-artifacts-private-samples-ignored",
            False,
            f"missing={missing}",
        )
    return CheckResult(
        "runtime-proof-local-artifacts-private-samples-ignored",
        True,
        "local Swift build artifacts, .vital files, real data, and TestKit "
        "fixtures are ignored from git and Docker build context, and "
        "documented as non-product inputs",
    )


def check_product_docs_do_not_promote_testkit_runtime_surface() -> CheckResult:
    docs = [
        ROOT / "Makefile",
        ROOT / "scripts/test_vitalserver.py",
        ROOT / "docs/pwa/index.md",
        ROOT / "docs/runtime/macos/update.md",
        ROOT / "docs/runtime/macos/runtime.md",
        ROOT / "docs/runtime/macos/architecture.md",
        ROOT / "docs/runtime/macos/observability.md",
        ROOT / "docs/runtime/macos/packaging.md",
        ROOT / "docs/adr/0002-helper-client-boundary-for-local-and-remote-runtime.md",
        ROOT / "docs/recorder/vital-recorder-integration.md",
        ROOT / "docs/product/productization.md",
        ROOT / "docs/product/release-dev-documentation-plan.md",
        ROOT / "apps/vitaldb-observer/README.md",
        ROOT / "site-docs/index.md",
        ROOT / "site-docs/dev/architecture.md",
        ROOT / "site-docs/dev/runtime-contracts.md",
        ROOT / "site-docs/dev/delivery-validation.md",
        ROOT / "site-docs/dev/repository-map.md",
        ROOT / "site-docs/release/usage.md",
        ROOT / "site-docs/release/runtime-status.md",
        ROOT / "docs/troubleshooting/070_golden-disk-runtime-boot-proof-gap.md",
    ]
    forbidden = {
        "Makefile": [
            "bounded productization smoke scenario",
            "Compose productization sandbox",
        ],
        "scripts/test_vitalserver.py": [
            "productization checks with the testkit CLI",
            "VitalServer productization checks",
        ],
        "docs/pwa/index.md": [
            "TestKit 전용 기능은 capability가 허용될 때만 노출",
        ],
        "docs/runtime/macos/update.md": [
            "testkit -> edge",
        ],
        "docs/runtime/macos/runtime.md": [
            "guest update activation/datastore repair request-result",
            "shared directory JSON contract, `RuntimeGuestGateway` port",
        ],
        "docs/runtime/macos/architecture.md": [
            "generated helper version/channel/testkit flag",
            "test-kit router implementation",
            "test-kit state policy",
            "runtime status/progress/health/guest request/result",
            "runtime-state.json, result JSON, guest logs",
            "legacy `vm-ip`",
            "guest request-result 계약",
        ],
        "docs/runtime/macos/observability.md": [
            "client/UI/testkit/external tools",
        ],
        "docs/runtime/macos/packaging.md": [
            "Test 탭/API 구현",
            "Test 탭과 local browser console",
            "Testkit API처럼 컨테이너로 제공되는 선택 서비스",
            "Test 탭의 route, API shape, 화면 정책",
            "guest activation request를 생성",
        ],
        "docs/adr/0002-helper-client-boundary-for-local-and-remote-runtime.md": [
            "TestKit/dev console 노출 여부",
            "`/dev/testkit/*` route만 test-enabled build 뒤에 둔다",
        ],
        "docs/recorder/vital-recorder-integration.md": [
            "Helper Test 탭 경로",
            "guest compose 안의 `testkit` container",
            "Helper/TestKit 제어",
            "`/dev/testkit` endpoint를 직접 제어",
        ],
        "docs/product/productization.md": [
            "운영 검증용 Python CLI/package",
            "Vital Recorder 또는 testkit이 Socket.IO",
            "검증은 testkit scenario로 재현",
        ],
        "docs/product/release-dev-documentation-plan.md": [
            "runtime/API/testkit 유지보수자",
            "observer/testkit 관계",
            "make install-testkit-release",
            "observer, testkit을 같은 guest",
            "release에서는 검증 도구로 제한 노출",
        ],
        "apps/vitaldb-observer/README.md": [
            "The final read model SoT is the macOS runtime observability SQLite file",
            "watchdog stores the embedded observation in\n"
            "`runtime-observability.sqlite`",
            "latest observation stored by watchdog/runtime",
        ],
        "site-docs/index.md": [
            "runtime/API/testkit 유지보수자",
            "observer, recorder ingress, testkit 포함",
        ],
        "site-docs/dev/architecture.md": [
            "-> Testkit API",
            "Redis, observer, recorder ingress, testkit, Vital Server wrapper 실행",
        ],
        "site-docs/dev/runtime-contracts.md": [
            "지원 예정 file reader / testkit policy",
            "Guest shutdown result",
            "Host는 request를 쓰고 Guest의 typed result를 기다립니다",
            "prepare-update-shutdown-result.json",
            "reconcile-compose.request",
            "request missing",
            "result missing",
            "result stale",
        ],
        "site-docs/dev/delivery-validation.md": [
            "observer, testkit, API client, package plan",
            "| testkit smoke | simulated recorder와 Vital Server 연결",
            "TestKit,\nobserver, websocket",
            "runtime 상태 표시를 바꿨다면 testkit을 함께 봅니다",
            "reconcile request/result contract",
            "prepare-update-shutdown.request",
            "prepare-update-shutdown-result.json",
            "Guest command request file",
            "request/result document",
            "Guest compose reconcile request/result contract",
            "reconcile-compose.request",
        ],
        "site-docs/dev/repository-map.md": [
            "runtime TestKit API",
            "`packages/vitalserver-testkit`와 runtime TestKit API",
            "가상 recorder와 smoke/load 검증 도구",
            "Contracts/RuntimeControl/TestKit/",
            "Adapters/Inbound/RuntimeControlAPI/TestKit/",
            "Adapters/Inbound/MacControlPanel/Presentation/TestKit/",
            "Adapters/Outbound/MacRuntimeControlClient/TestKit/",
            "| testkit endpoint",
            "| testkit control",
        ],
        "site-docs/release/usage.md": [
            "Helper Test 탭의 `Manual .vital upload`",
        ],
        "site-docs/release/runtime-status.md": [
            "guest runtime-state의 `containerServices` 계약",
            "containerObservation.composeServicesReadState",
            "prepare-update-shutdown.request",
            "prepare-update-shutdown-result.json",
            "Guest shutdown request는 single-shot contract",
            "request file을 poweroff 직전까지",
        ],
        "docs/troubleshooting/070_golden-disk-runtime-boot-proof-gap.md": [
            "dev build에서 `testkit`만 누락",
            "testkit이 몇 초 뒤 등장",
            "late-ready compose services",
            "expected service가 runtime-state에 아직 없으면",
        ],
    }
    required = {
        "Makefile": [
            "bounded dev verification smoke scenario",
            "Compose development sandbox through host proxy",
            "Compose development sandbox, Swagger, and dev testkit targets",
        ],
        "scripts/test_vitalserver.py": [
            "developer verification checks with the testkit CLI",
            "VitalServer developer verification checks",
        ],
        "docs/pwa/index.md": [
            "Product Lab 기능은 `/lab/*` Runtime Control API 계약으로만 노출",
        ],
        "docs/runtime/macos/update.md": [
            "lab -> vitaldb-observer -> redis-relay",
            "recorder-ingress -> recorder-recovery -> app -> postgres -> redis",
        ],
        "docs/runtime/macos/runtime.md": [
            "guest update activation/datastore repair operation",
            "Guest Control maintenance API, Guest operation document",
        ],
        "docs/runtime/macos/architecture.md": [
            "generated helper version/channel metadata",
            "Product Lab routes, Guest service routes, VitalDB read routes",
            "runtime status/progress/health/Guest Control",
            "Guest Control operation/read documents",
            "VM IP/bootstrap HTTP readiness",
            "Guest Control operation 계약",
            "removed legacy request/result file workflow",
        ],
        "docs/runtime/macos/observability.md": [
            "PWA, Swift UI, CLI, external product tools",
        ],
        "docs/runtime/macos/packaging.md": [
            "Product Lab/API 구현의 세부 contract",
            "Local browser diagnostics console은 `dev`에서만 노출",
            "Product Lab과 Postgres는 선택 TestKit service가 아니라",
            "Runtime Control `/lab/*`, Guest Control `/v1/lab/*`, "
            "`apps/vitalserver-lab`",
            "Guest Control update activation operation을 생성",
        ],
        "docs/adr/0002-helper-client-boundary-for-local-and-remote-runtime.md": [
            "`/runtime/*`, `/vitaldb/*`, `/host/*`, `/lab/*`",
            "Legacy `/dev/testkit/*` route는 Runtime v2 product surface가 아니며",
            "Product Lab 계약으로 노출한다",
        ],
        "docs/recorder/vital-recorder-integration.md": [
            "Helper Product Lab 경로",
            "Runtime Control API `/lab/*`",
            "Guest Control API `/v1/lab/*`",
            "apps/vitalserver-lab",
        ],
        "docs/product/productization.md": [
            "apps/vitalserver-lab/",
            "dev/load 검증용 Python CLI/package",
            "Vital Recorder 또는 dev testkit",
            "Runtime v2 제품 runtime의 virtual recorder",
            "Product Lab service가 소유합니다.",
        ],
        "docs/product/release-dev-documentation-plan.md": [
            "runtime/API/Product Lab/dev testkit 유지보수자",
            "observer/Product Lab/dev testkit 검증 관계",
            "dev-only `make testkit/install-release`",
            "Product Lab을 같은 guest 기준",
            "release runtime에는 포함하지 않음",
        ],
        "apps/vitaldb-observer/README.md": [
            "The final product read model SoT is the Guest/Postgres VitalDB read model",
            "SQLite can remain as diagnostics or migration evidence only",
            "latest Guest/Postgres-backed observation read model",
        ],
        "site-docs/index.md": [
            "runtime/API/Product Lab/dev testkit 유지보수자",
            "Product Lab, observer, recorder ingress, dev testkit 포함",
        ],
        "site-docs/dev/architecture.md": [
            "-> Product Lab API",
            "Redis, observer, recorder ingress, Product Lab, Vital Server wrapper 실행",
        ],
        "site-docs/dev/runtime-contracts.md": [
            "Product Lab / Guest Control file policy",
            "Guest Control shutdown operation",
            "Host는 Guest Control maintenance API로",
            "Guest Control stack reconcile operation",
            "accepted",
            "unavailable",
        ],
        "site-docs/dev/delivery-validation.md": [
            "observer, Product Lab/dev testkit, API client, package plan",
            "| testkit smoke | dev simulated recorder와 Vital Server 연결",
            "Product Lab,\ndev testkit, observer",
            "Product Lab 경로와 dev testkit 검증을 함께 봅니다",
            "Guest Control stack reconcile operation",
            "Guest Control update-shutdown operation",
            "Guest Control operation document",
            "`/v1/operations/{operationId}`",
        ],
        "site-docs/dev/repository-map.md": [
            "Product Lab 수정",
            "`apps/vitalserver-lab`, Runtime Control `/lab/*`, "
            "Guest Control `/v1/lab/*`",
            "dev testkit 수정",
            "`apps/vitalserver-lab`",
            "dev-only simulated recorder와 smoke/load 검증 도구",
            "Product Lab과 Dev Console",
            "Adapters/Inbound/MacControlPanel/Presentation/Lab/",
            "Adapters/Outbound/GuestControl/",
            "Contracts/Shared/RuntimeLabContracts.swift",
            "| Product Lab route",
            "| Guest service/Lab/VitalDB API",
        ],
        "site-docs/release/usage.md": [
            "Helper Product Lab의 `.vital` replay/upload 흐름",
        ],
        "site-docs/release/runtime-status.md": [
            "Guest Control API가 제공하는 service/stack status 계약",
            "Guest Control update-shutdown operation",
            "Guest shutdown command는 single-shot operation",
        ],
        "docs/troubleshooting/070_golden-disk-runtime-boot-proof-gap.md": [
            "Product Lab 또는 다른 required product service",
            "Guest Control `/v1/stack/status` 응답",
            "product stack services",
            "late-ready product services",
        ],
    }
    texts = {relative(path): read(path) for path in docs}
    matches = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    if matches or missing:
        return CheckResult(
            "product-docs-no-testkit-runtime-surface",
            False,
            f"matches={matches} missing={missing}",
        )
    return CheckResult(
        "product-docs-no-testkit-runtime-surface",
        True,
        "product docs route Lab through v2 contracts and do not promote "
        "TestKit runtime surface wording",
    )


def check_runtime_proof_docs_describe_acceptance_targets() -> CheckResult:
    path = ROOT / "docs/runtime/macos/runtime-guest-control.md"
    text = read(path)
    required = [
        "Runtime v2 review and acceptance proof",
        "make runtime/proof/review",
        "runtime/proof/no-v1-service-state",
        "runtime/proof/python-focused",
        "pwa/check",
        "pwa/test",
        "pwa/build",
        "make runtime/proof/acceptance",
        "runtime/proof/swift-focused",
        "runtime/proof/http-e2e",
        "runtime/proof/smoke",
        "Runtime v2 is not complete until the final acceptance gate passes",
        "VM_RUNTIME_PROOF_SWIFT_FOCUSED_FILTER",
        "make runtime/proof/http-e2e",
        "aliases `runtime/e2e/smoke`",
        "core read endpoints over loopback",
    ]
    missing = [token for token in required if token not in text]
    if missing:
        return CheckResult(
            "runtime-proof-docs-acceptance-targets",
            False,
            f"missing={missing} path={relative(path)}",
        )
    return CheckResult(
        "runtime-proof-docs-acceptance-targets",
        True,
        "Runtime v2 docs describe review, Swift focused, HTTP E2E, and "
        "VM smoke acceptance gates",
    )


def check_api_catalog_exposes_runtime_support_specs() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Support/Guest/compose.yaml",
        PWA / "src/pages/advanced/AdvancedPage.tsx",
        PWA / "src/pages/pages.test.tsx",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Copy"
            / "AppConstants+Product.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Views"
            / "RuntimeAdvancedPanel.swift"
        ),
        ROOT / "docs/runtime/macos/runtime-guest-control.md",
    ]
    texts = {relative(path): read(path) for path in paths}
    required = {
        "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml": [
            'BASE_URL: "/swagger"',
            '{"name":"VitalServer","url":"/swagger/docs/openapi.yaml"}',
            (
                '{"name":"Runtime Control API","url":'
                '"/swagger/docs/macos-runtime/runtime-control.openapi.json"}'
            ),
            (
                '{"name":"Recorder Ingress","url":'
                '"/swagger/docs/openapi/recorder-ingress.openapi.yaml"}'
            ),
            (
                '{"name":"VitalDB Observer","url":'
                '"/swagger/docs/openapi/vitaldb-observer.openapi.yaml"}'
            ),
            "source: /mnt/tirosh/deploy/docs",
            "target: /usr/share/nginx/html/docs",
        ],
        "apps/vitalserver-runtime-pwa/src/pages/advanced/AdvancedPage.tsx": [
            'label: "Swagger UI"',
            'label: "VitalServer API"',
            'label: "Runtime Control API"',
            (
                "value: `${baseURL}/swagger/docs/macos-runtime/"
                "runtime-control.openapi.json`"
            ),
            'label: "Recorder Ingress API"',
            'label: "VitalDB Observer API"',
        ],
        "apps/vitalserver-runtime-pwa/src/pages/pages.test.tsx": [
            'screen.getByText("API catalog")',
            'screen.getByText("VitalServer API")',
            'screen.getByText("Runtime Control API")',
            'screen.getByText("Recorder Ingress API")',
            'screen.getByText("VitalDB Observer API")',
            "http://127.0.0.1:18080/swagger/docs/macos-runtime/runtime-control.openapi.json",
        ],
        (
            "apps/vitalserver-macos-runtime/Sources/Adapters/Inbound"
            "/MacControlPanel/Presentation/Copy/AppConstants+Product.swift"
        ): [
            "/swagger/docs/openapi.yaml",
            "/swagger/docs/macos-runtime/runtime-control.openapi.json",
            "/swagger/docs/openapi/recorder-ingress.openapi.yaml",
            "/swagger/docs/openapi/vitaldb-observer.openapi.yaml",
        ],
        (
            "apps/vitalserver-macos-runtime/Sources/Adapters/Inbound"
            "/MacControlPanel/Presentation/Views/RuntimeAdvancedPanel.swift"
        ): [
            'label: "Swagger UI"',
            'label: "VitalServer API"',
            'label: "Runtime Control API"',
            'label: "Recorder Ingress API"',
            'label: "VitalDB Observer API"',
            "apiCatalogItems(proxyPort:",
        ],
        "docs/runtime/macos/runtime-guest-control.md": [
            "API catalog is a support surface, not a state source",
            "VitalServer API -> /swagger/docs/openapi.yaml",
            (
                "Runtime Control API -> "
                "/swagger/docs/macos-runtime/runtime-control.openapi.json"
            ),
            (
                "Recorder Ingress API -> "
                "/swagger/docs/openapi/recorder-ingress.openapi.yaml"
            ),
            (
                "VitalDB Observer API -> "
                "/swagger/docs/openapi/vitaldb-observer.openapi.yaml"
            ),
            "Until those internal services publish explicit support OpenAPI",
            "must not invent direct Swagger entries",
        ],
    }
    forbidden_tokens = [
        "/dev/testkit",
        "Runtime TestKit API",
        '{"name":"TestKit"',
        'label: "TestKit API"',
        "testkit.openapi",
    ]
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    catalog_paths = [
        "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml",
        "apps/vitalserver-runtime-pwa/src/pages/advanced/AdvancedPage.tsx",
        (
            "apps/vitalserver-macos-runtime/Sources/Adapters/Inbound"
            "/MacControlPanel/Presentation/Views/RuntimeAdvancedPanel.swift"
        ),
    ]
    forbidden = [
        f"{path}:{token}"
        for path in catalog_paths
        for text in [texts[path]]
        for token in forbidden_tokens
        if token in text
    ]
    if missing or forbidden:
        return CheckResult(
            "api-catalog-runtime-support-specs",
            False,
            f"missing={missing} forbidden={forbidden}",
        )
    return CheckResult(
        "api-catalog-runtime-support-specs",
        True,
        "Swagger/PWA/Swift API catalogs expose Runtime v2 support specs "
        "without TestKit or direct internal Guest state entries",
    )


def check_runtime_proof_troubleshooting_documents_acceptance_blockers(
) -> CheckResult:
    path = (
        ROOT
        / "docs/troubleshooting/"
        / "099_runtime-acceptance-environment-blockers.md"
    )
    text = read(path)
    required = [
        "Runtime v2 acceptance is blocked by local environment restrictions",
        "make runtime/proof/review",
        "make runtime/proof/acceptance",
        "make runtime/proof/swift-focused",
        "make runtime/proof/http-e2e",
        "make runtime/proof/smoke",
        "sandbox-exec: sandbox_apply: Operation not permitted",
        "PermissionError: [Errno 1] Operation not permitted: 'ps'",
        "Docker credential",
        "make -n runtime/proof/acceptance",
        "does not prove a Runtime v2 code failure",
        "Runtime v2 is not complete until the final acceptance gate passes",
        "aliases `runtime/e2e/smoke`",
    ]
    missing = [token for token in required if token not in text]
    if missing:
        return CheckResult(
            "runtime-proof-troubleshooting-acceptance-blockers",
            False,
            f"missing={missing} path={relative(path)}",
        )
    return CheckResult(
        "runtime-proof-troubleshooting-acceptance-blockers",
        True,
        "Runtime v2 troubleshooting documents acceptance environment "
        "blockers without treating them as code success or code failure",
    )


def check_maintenance_docs_do_not_promote_request_files_as_current_path(
) -> CheckResult:
    docs = [
        ROOT / "docs/runtime/macos/update.md",
        ROOT / "docs/runtime/macos/runtime-data-backup.md",
    ]
    forbidden = {
        "docs/runtime/macos/update.md": [
            "activation request reader:",
            "activation result writer:",
            "이 shutdown request는 update-specific operation",
            "`prepare-update-shutdown` capability를 보고한 경우에만 request를 쓴다",
            "Guest worker는 request를 읽고 `running` result를 기록",
            "invalid request apply",
            "request consume, ordered compose stop",
        ],
        "docs/runtime/macos/runtime-data-backup.md": [
            "guest `redis-restore` request/result",
        ],
    }
    required = {
        "docs/runtime/macos/update.md": [
            "Guest activation은 Guest Control maintenance operation으로 실행합니다.",
            "activation operation input:",
            "activation operation result:",
            "operation accepted",
            "invalid operation apply",
        ],
        "docs/runtime/macos/runtime-data-backup.md": [
            "Guest Control `redis-restore` maintenance operation",
        ],
    }
    texts = {relative(path): read(path) for path in docs}
    matches = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    if matches or missing:
        return CheckResult(
            "maintenance-docs-no-current-request-files",
            False,
            f"matches={matches} missing={missing}",
        )
    return CheckResult(
        "maintenance-docs-no-current-request-files",
        True,
        "maintenance docs describe Guest Control operation documents instead "
        "of v1 request/result files as the current path",
    )


def check_observer_docs_use_guest_postgres_read_model_flow() -> CheckResult:
    packaging_path = ROOT / "docs/runtime/macos/packaging.md"
    observability_path = ROOT / "docs/runtime/macos/observability.md"
    texts = {
        relative(packaging_path): read(packaging_path),
        relative(observability_path): read(observability_path),
    }
    forbidden = {
        relative(packaging_path): [
            (
                "-> guest runtime-state.json\n"
                "  -> watchdog\n"
                "  -> runtime-observability.sqlite\n"
                "  -> Runtime Control API /vitaldb/*"
            ),
        ],
        relative(observability_path): [
            (
                "-> vitaldb-observer snapshot\n"
                "  -> guest runtime-state.json"
            ),
            "VitalDB observer snapshot",
            "compose service health summary를 recovery trigger와 연결",
        ],
    }
    required = {
        relative(packaging_path): [
            "-> Guest Control VitalDB writer",
            "-> Postgres read model",
            "-> Guest Control API /v1/vitaldb/*",
        ],
        relative(observability_path): [
            "-> Guest/Postgres VitalDB read model",
            "-> Guest Control API /v1/vitaldb/*",
            "Guest Control API VitalDB read model read state",
        ],
    }
    matches = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    if matches or missing:
        return CheckResult(
            "observer-docs-guest-postgres-read-model-flow",
            False,
            f"matches={matches} missing={missing}",
        )
    return CheckResult(
        "observer-docs-guest-postgres-read-model-flow",
        True,
        "observer packaging docs route VitalDB observations through "
        "Guest/Postgres read models",
    )


def check_redis_backup_restore_results_do_not_carry_request_id() -> CheckResult:
    forbidden = [
        "request_id = \"\"",
        "request_id: str = \"\"",
        "request_id: str",
        "requestId",
        "outcome.request_id",
        "request_id=outcome.request_id",
    ]
    contexts_path = GUEST_TOOLS / "src/tirosh_guest_tools/application/contexts.py"
    models_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/domain/guest_control/models.py"
    )
    redis_backup_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/redis_backup.py"
    )
    redis_restore_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/redis_restore.py"
    )
    adapter_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/maintenance"
        / "redis_backup.py"
    )
    contexts = read(contexts_path)
    models = read(models_path)
    snippets = {
        f"{relative(contexts_path)}:RedisBackupOutcome": text_between(
            contexts,
            "class RedisBackupOutcome",
            "class RedisRestoreOutcome",
        ),
        f"{relative(contexts_path)}:RedisRestoreOutcome": text_between(
            contexts,
            "class RedisRestoreOutcome",
            "class __end_of_redis_restore_outcome__",
        ),
        f"{relative(models_path)}:RedisBackupResult": text_between(
            models,
            "class RedisBackupResult",
            "class RedisRestoreDependencyError",
        ),
        f"{relative(models_path)}:RedisRestoreResult": text_between(
            models,
            "class RedisRestoreResult",
            "class UpdateActivationDependencyError",
        ),
        relative(redis_backup_path): read(redis_backup_path),
        relative(redis_restore_path): read(redis_restore_path),
        relative(adapter_path): read(adapter_path),
    }
    matches = [
        f"{name}:{token}"
        for name, text in snippets.items()
        for token in forbidden
        if token in text
    ]
    if matches:
        return CheckResult(
            "redis-backup-restore-results-no-request-id",
            False,
            f"matches={matches}",
        )
    return CheckResult(
        "redis-backup-restore-results-no-request-id",
        True,
        "Redis backup/restore results use Guest Control operation identity "
        "instead of carrying legacy request ids",
    )


def check_guest_tools_legacy_operation_result_model_removed() -> CheckResult:
    paths = [
        GUEST_TOOLS / "src/tirosh_guest_tools/domain/operations.py",
        GUEST_TOOLS / "tests/test_operations.py",
    ]
    forbidden = [
        "class OperationStatus",
        "class OperationName",
        "class ShutdownPhase",
        "class ReasonCode",
        "class GuestOperationRequest",
        "class GuestOperationResult",
        "requestId",
        "schema_version",
        "schemaVersion",
    ]
    existing_paths = [path for path in paths if path.exists()]
    matches = find_tokens(existing_paths, forbidden)
    if matches:
        return CheckResult(
            "guest-tools-legacy-operation-result-model-removed",
            False,
            f"matches={matches}",
        )
    return CheckResult(
        "guest-tools-legacy-operation-result-model-removed",
        True,
        "guest-tools legacy request/result operation DTOs are removed; "
        "Guest Control operation documents own maintenance operation state",
    )


def check_vitaldb_read_models_do_not_name_host_sqlite_as_source() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Contracts/RuntimeControl",
        MACOS_RUNTIME / "Tests",
        PWA / "src",
        ROOT / "docs/runtime/macos",
    ]
    forbidden = [
        "sqliteProjection",
        "runtime observability SQLite projection",
        "최종 observation SoT는 watchdog/runtime observability SQLite",
        "final observation SoT is watchdog/runtime observability SQLite",
        "VitalDB observer + host observability projection",
        "latest observation snapshot, SQLite projection",
        "Host observability projection owns SQLite read model.",
    ]
    matches = find_tokens(paths, forbidden)
    if matches:
        return CheckResult(
            "vitaldb-read-models-no-host-sqlite-source",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "vitaldb-read-models-no-host-sqlite-source",
        True,
        "VitalDB read-model contracts do not name Host SQLite as product source",
    )


def check_vitaldb_host_sqlite_projection_requires_diagnostics_mode() -> CheckResult:
    product_reader_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeObservabilityReader.swift"
    )
    diagnostics_reader_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeVitalDBHostDiagnosticsProjectionReader.swift"
    )
    product_reader = read(product_reader_path)
    diagnostics_reader = read(diagnostics_reader_path)
    required = [
        "enum RuntimeVitalDBHostProjectionReadMode",
        "case diagnostics",
        "mode: RuntimeVitalDBHostProjectionReadMode = .disabled",
        "guard mode == .diagnostics else",
        "host SQLite observation projection is disabled",
        "host SQLite activity projection is disabled",
        "host SQLite relationship projection is disabled",
        "RuntimeVitalDBProjectionReadCollector",
    ]
    reader_forbidden = [
        "RuntimeVitalDBHostDiagnosticsProjectionReader",
        "RuntimeVitalDBProjectionReadCollector(",
        "SQLiteVitalDBObservationRepository(url:",
        "hostProjectionReadMode:",
        "makeVitalDBProjectionRepository:",
        "guard hostProjectionReadMode == .diagnostics else",
    ]
    forbidden = [
        "fallback projection only when Guest current observation is unavailable",
        "Guest current observation is unavailable",
    ]
    missing = [token for token in required if token not in diagnostics_reader]
    present = [
        token
        for token in forbidden
        if token in product_reader or token in diagnostics_reader
    ]
    reader_present = [token for token in reader_forbidden if token in product_reader]
    if missing or present or reader_present:
        return CheckResult(
            "vitaldb-host-sqlite-explicit-diagnostics-only",
            False,
            (
                f"missing={missing} forbidden_present={present} "
                f"reader_forbidden={reader_present}"
            ),
        )
    return CheckResult(
        "vitaldb-host-sqlite-explicit-diagnostics-only",
        True,
        "Host SQLite VitalDB projection reads require explicit diagnostics mode",
    )


def check_host_does_not_write_vitaldb_sqlite_projection() -> CheckResult:
    lifecycle_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Support"
        / "RuntimeLifecycle+ObservabilitySupport.swift"
    )
    publisher_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/Observability"
        / "RuntimeObservedStatusPublisher.swift"
    )
    removed_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/ObservabilityStore"
            / "RuntimeVitalDBObservationProjector.swift"
        ),
        (
            MACOS_RUNTIME
            / "Tests/OutboundAdaptersTests"
            / "RuntimeVitalDBObservationProjectorTests.swift"
        ),
    ]
    scan_paths = [lifecycle_path, publisher_path]
    forbidden = [
        "RuntimeVitalDBObservationProjector",
        "SQLiteVitalDBObservationRepository(store:",
        "projectVitalDBObservationBestEffort",
        "projectObservation",
        "appendObservation:",
    ]
    existing = [relative(path) for path in removed_paths if path.exists()]
    matches = find_tokens(scan_paths, forbidden)
    if existing or matches:
        return CheckResult(
            "host-no-vitaldb-sqlite-projection-writes",
            False,
            f"existing={existing} matches={matches[:10]}",
        )
    return CheckResult(
        "host-no-vitaldb-sqlite-projection-writes",
        True,
        "Host status publishing does not write VitalDB observations into Host SQLite",
    )


def check_host_health_does_not_promote_vitaldb_read_model_failures() -> CheckResult:
    policy_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Domain/Policies"
            / "RuntimeObservationHealthPolicy.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Domain/Policies"
            / "RuntimeWatchdogRecoveryPolicy.swift"
        ),
    ]
    contract_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared"
            / "RuntimeFailureReason.swift"
        ),
    ]
    policy_forbidden = [
        ".vitalDBObservationMissing",
        ".vitalDBObservationReadFailed",
        ".vitalDBObservationStale",
        ".vitalDBAnomaly(",
        "vitalDBFailureReasons",
    ]
    contract_forbidden = [
        ".vitalDBObservationMissing",
        ".vitalDBObservationReadFailed",
        ".vitalDBObservationStale",
        "case vitalDBObservationMissing",
        "case vitalDBObservationReadFailed",
        "case vitalDBObservationStale",
        "vitaldb-observation-missing",
        "vitaldb-observation-read-failed",
        "vitaldb-observation-stale",
    ]
    matches = find_tokens(policy_paths, policy_forbidden)
    matches += find_tokens(contract_paths, contract_forbidden)
    if matches:
        return CheckResult(
            "host-health-no-vitaldb-read-model-failures",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "host-health-no-vitaldb-read-model-failures",
        True,
        (
            "Host runtime health does not promote VitalDB read-model failures "
            "into recovery reasons"
        ),
    )


def check_health_recovery_policies_do_not_accept_diagnostics_observations(
) -> CheckResult:
    checks = {
        MACOS_RUNTIME
        / "Sources/Domain/Policies/RuntimeObservationHealthPolicy.swift": [
            "containerObservation:",
            "containerObservationDiagnostics",
            "vitalDBObservation:",
        ],
        MACOS_RUNTIME
        / "Sources/Domain/Policies/RuntimeRecoveryPlanner.swift": [
            "public let containerObservation",
            "containerObservation:",
            "containerObservationDiagnostics",
        ],
    }
    matches: list[str] = []
    for path, tokens in checks.items():
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token}")
    if matches:
        return CheckResult(
            "health-recovery-no-diagnostics-observation-inputs",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "health-recovery-no-diagnostics-observation-inputs",
        True,
        (
            "Health failure and recovery planning policies do not accept "
            "container/VitalDB diagnostics observations as decision inputs"
        ),
    )


def check_current_health_filters_legacy_runtime_state_vm_errors(
) -> CheckResult:
    policy_path = (
        MACOS_RUNTIME / "Sources/Domain/Policies/RuntimeVMHealthPolicy.swift"
    )
    tests_path = (
        MACOS_RUNTIME
        / "Tests/DomainTests/Policies/RuntimeHealthEvaluatorTests.swift"
    )
    policy_text = read(policy_path)
    tests_text = read(tests_path)
    required = {
        relative(policy_path): [
            "currentHealthVMErrors(input.reportedVMErrors)",
            "case .runtimeStateMissing, .runtimeStateInvalid, .runtimeStateStale:",
            "return false",
        ],
        relative(tests_path): [
            "testLegacyRuntimeStateVMErrorsAreNotCurrentHealthInput",
            "reportedVMErrors: [",
            ".runtimeStateMissing",
            ".runtimeStateInvalid",
            ".runtimeStateStale",
            "XCTAssertEqual(snapshot.vmErrors, [])",
        ],
    }
    texts = {
        relative(policy_path): policy_text,
        relative(tests_path): tests_text,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    if missing:
        return CheckResult(
            "current-health-filters-legacy-runtime-state-vm-errors",
            False,
            f"missing={missing}",
        )
    return CheckResult(
        "current-health-filters-legacy-runtime-state-vm-errors",
        True,
        "Current health evaluation filters legacy runtime-state VM errors",
    )


def check_health_snapshot_contract_does_not_carry_container_observation(
) -> CheckResult:
    snapshot_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeHealthSnapshot.swift"
    )
    evaluator_path = (
        MACOS_RUNTIME
        / "Sources/Domain/Policies/RuntimeHealthEvaluator.swift"
    )
    snapshot_text = read(snapshot_path)
    evaluator_text = read(evaluator_path)
    runtime_health_input = text_between(
        evaluator_text,
        "public struct RuntimeHealthInput",
        "public enum RuntimeHealthEvaluator",
    )
    runtime_health_observation = text_between(
        read(
            MACOS_RUNTIME
            / "Sources/Application/UseCases/RuntimeHealth"
            / "EvaluateRuntimeHealthUseCase.swift"
        ),
        "public struct RuntimeHealthObservation",
        "public struct RuntimeGuestReadinessInputPlan",
    )
    checks = {
        relative(snapshot_path): snapshot_text,
        f"{relative(evaluator_path)}:RuntimeHealthInput": runtime_health_input,
        (
            "apps/vitalserver-macos-runtime/Sources/Application/UseCases/"
            "RuntimeHealth/EvaluateRuntimeHealthUseCase.swift:"
            "RuntimeHealthObservation"
        ): runtime_health_observation,
        (
            "apps/vitalserver-macos-runtime/Sources/Contracts/Shared/"
            "RuntimeHealthObservationReads.swift"
        ): read(
            MACOS_RUNTIME
            / "Sources/Contracts/Shared/RuntimeHealthObservationReads.swift"
        ),
        (
            "apps/vitalserver-macos-runtime/Sources/Adapters/Outbound/Health/"
            "RuntimeHealthChecker.swift"
        ): read(
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Health/RuntimeHealthChecker.swift"
        ),
    }
    forbidden = [
        "public let containerObservation",
        "containerObservation: RuntimeObservationInput<RuntimeContainerObservation>",
        "containerObservation: RuntimeContainerObservation?",
        "containerObservation:",
        "runtimeStateFileModifiedAt",
        "RuntimeFileModifiedAtReadResult",
        "RuntimeFileMetadataReadState",
        "RuntimeFileModifiedAtReader",
    ]
    matches: list[str] = []
    for label, text in checks.items():
        present = [token for token in forbidden if token in text]
        if present:
            matches.append(f"{label}:{present}")
    if matches:
        return CheckResult(
            "health-snapshot-contract-no-container-observation",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "health-snapshot-contract-no-container-observation",
        True,
        "Runtime health input/snapshot contracts do not carry container "
        "diagnostics or runtime-state file metadata",
    )


def check_runtime_status_document_does_not_store_vitaldb_observation() -> CheckResult:
    document_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared"
        / "RuntimeStatusDocument.swift"
    )
    builder_path = (
        MACOS_RUNTIME
        / "Sources/Domain/Models"
        / "RuntimeStatusDocumentBuilder.swift"
    )
    reporting_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeOperationReporting"
        / "BuildRuntimeStatusDocumentUseCase.swift"
    )
    texts = {
        relative(document_path): read(document_path),
        relative(builder_path): read(builder_path),
        relative(reporting_path): read(reporting_path),
    }
    forbidden = {
        relative(document_path): [
            "public let vitalDBObservation",
            "vitalDBObservation: VitalDBObservationDocument?",
            "self.vitalDBObservation",
        ],
        relative(builder_path): [
            "vitalDBObservation:",
            "vitalDBObservation: input.healthSnapshot.vitalDBObservation",
        ],
        relative(reporting_path): [
            "vitalDBObservation:",
            "vitalDBObservation: input.current.vitalDBObservation",
        ],
    }
    present = {
        path: [token for token in tokens if token in texts[path]]
        for path, tokens in forbidden.items()
        if any(token in texts[path] for token in tokens)
    }
    if present:
        return CheckResult(
            "runtime-status-document-no-vitaldb-observation-write",
            False,
            f"forbidden_present={present}",
        )
    return CheckResult(
        "runtime-status-document-no-vitaldb-observation-write",
        True,
        "Host runtime-status document contract does not carry VitalDB observations",
    )


def check_runtime_status_contract_has_no_vitaldb_observation() -> CheckResult:
    swift_status_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl"
        / "RuntimeControlModels.swift"
    )
    swift_assembly_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl"
        / "RuntimeStatusAssembly.swift"
    )
    swift_overview_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl"
        / "RuntimeControlReadModels.swift"
    )
    dev_console_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/DevConsole"
        / "RuntimeControlDevConsole.html"
    )
    pwa_schema_path = (
        PWA
        / "src/domain/runtime-control/contracts/schemas"
        / "runtimeControlSchemas.ts"
    )
    pwa_generated_path = (
        PWA
        / "src/domain/runtime-control/contracts/generated"
        / "runtime-control.ts"
    )
    openapi_path = ROOT / "docs/runtime/macos/runtime-control.openapi.json"

    checks = {
        relative(swift_status_path): [
            "public var vitalDBObservation",
            "case vitalDBObservation",
            "guestRuntimeStateError",
        ],
        relative(swift_assembly_path): [
            "vitalDBObservation: nil",
            "guestRuntimeStateError:",
        ],
        relative(swift_overview_path): [
            "statusWithoutLegacyVitalDBObservation",
            ".vitalDBObservation = nil",
        ],
        relative(dev_console_path): [
            "status.vitalDBObservation",
            "latestStatus.vitalDBObservation",
        ],
    }
    matches: list[str] = []
    for path_text, tokens in checks.items():
        path = ROOT / path_text
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{path_text}:{token}")

    pwa_schema = read(pwa_schema_path)
    pwa_status_block = text_between(
        pwa_schema,
        "export const runtimeStatusSchema",
        "const runtimeVitalRecorderSummarySchema",
    )
    for token in ["vitalDBObservation", "guestRuntimeStateError"]:
        if token in pwa_status_block:
            matches.append(f"{relative(pwa_schema_path)}:runtimeStatusSchema.{token}")

    pwa_generated = read(pwa_generated_path)
    pwa_generated_status_block = text_between(
        pwa_generated,
        "RuntimeStatus: {",
        "RuntimeEventHistory:",
    )
    for token in ["vitalDBObservation", "guestRuntimeStateError"]:
        if token in pwa_generated_status_block:
            matches.append(f"{relative(pwa_generated_path)}:RuntimeStatus.{token}")

    openapi = read(openapi_path)
    openapi_status_block = text_between(
        openapi,
        '"RuntimeStatus": {',
        '"RuntimeEventHistory":',
    )
    for token in ['"vitalDBObservation"', '"guestRuntimeStateError"']:
        if token in openapi_status_block:
            matches.append(f"{relative(openapi_path)}:RuntimeStatus.{token}")

    if matches:
        return CheckResult(
            "runtime-status-contract-no-vitaldb-observation",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-status-contract-no-vitaldb-observation",
        True,
        "RuntimeStatus contract does not carry legacy VitalDB or "
        "runtime-state error fields",
    )


def check_host_health_uses_guest_control_ready_for_guest_readiness() -> CheckResult:
    health_checker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Health/RuntimeHealthChecker.swift"
    )
    gateway_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/GuestControl/HTTPRuntimeGuestControlGateway.swift"
    )
    protocol_path = (
        MACOS_RUNTIME
        / "Sources/Application/Ports/RuntimeGuestControlGateway.swift"
    )
    contract_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeGuestControlContracts.swift"
    )
    health_usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeHealth"
        / "EvaluateRuntimeHealthUseCase.swift"
    )
    status_reader_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeStatusReader.swift"
    )
    gateway_tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests/HTTPRuntimeGuestControlGatewayTests.swift"
    )
    health_tests_path = (
        MACOS_RUNTIME
        / "Tests/ApplicationTests/EvaluateRuntimeHealthUseCaseTests.swift"
    )
    health_checker = read(health_checker_path)
    gateway = read(gateway_path)
    protocol = read(protocol_path)
    contract = read(contract_path)
    health_usecase = read(health_usecase_path)
    status_reader = read(status_reader_path)
    gateway_tests = read(gateway_tests_path)
    health_tests = read(health_tests_path)
    required = {
        relative(health_checker_path): [
            "guestControlReadiness()",
            "guestControlGateway(baseURL).ready()",
            "readVMIPFile()",
        ],
        relative(gateway_path): [
            "func ready() throws -> RuntimeGuestControlReadiness",
            'path: "/ready"',
            "decoder.decode(RuntimeGuestControlReadiness.self, from: response.data)",
        ],
        relative(protocol_path): [
            "func ready() throws -> RuntimeGuestControlReadiness",
        ],
        relative(contract_path): [
            "public let dependencies: [RuntimeGuestControlReadinessDependency]",
            "public struct RuntimeGuestControlReadinessDependency",
            "public var failureSummary: String?",
        ],
        relative(health_usecase_path): [
            "guestReadinessInputPlan(",
            "case .notReported:",
            "RuntimeGuestReadinessInputPlan(state: .notReported)",
            "readiness.failureSummary",
            ".probeFailed(\"\\(readiness.status):\\(failureSummary)\")",
        ],
        relative(status_reader_path): [
            "guestControlGateway(baseURL).ready()",
            "RuntimeControlClientConstants.Product.guestControlAPIBaseURL(vmIP: vmIP)",
            "guest control readiness failed:",
            "readiness.failureSummary",
        ],
        relative(gateway_tests_path): [
            '"dependencies": [',
            "RuntimeGuestControlReadinessDependency(",
            "testReadyDecodesDependencyFailureDocumentFromServiceUnavailableResponse",
            "statusCode: 503",
        ],
        relative(health_tests_path): [
            "testObservationPreservesGuestControlReadinessDependencyFailure",
            "postgresCommandFailed",
        ],
    }
    texts = {
        relative(health_checker_path): health_checker,
        relative(gateway_path): gateway,
        relative(protocol_path): protocol,
        relative(contract_path): contract,
        relative(health_usecase_path): health_usecase,
        relative(status_reader_path): status_reader,
        relative(gateway_tests_path): gateway_tests,
        relative(health_tests_path): health_tests,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = {
        relative(health_usecase_path): [
            "currentHealthGuestRuntimeStateReadFailures",
            "RuntimeGuestRuntimeStatePolicy.inputAssessment",
            "RuntimeGuestRuntimeStateInput",
            "RuntimeGuestRuntimeStateInputPlan",
            "guestRuntimeStateInputPlan(",
            "guestRuntimeState:",
            "observation.guestRuntimeState",
            "freshState: reads.guestRuntimeState.freshState",
            "loadedState: reads.guestRuntimeState.loadedState",
            "reads.guestRuntimeState.freshState?.diskHealth",
            "guestRuntimeStateReadFailureReasons",
            "reportedVMErrors(from diskHealth",
        ],
        relative(status_reader_path): [
            "RuntimeControlClientConstants.Product.guestHealthURL(vmIP: vmIP)",
        ],
    }
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    if missing or present:
        return CheckResult(
            "host-health-guest-control-ready",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "host-health-guest-control-ready",
        True,
        "Host health uses Guest Control /ready for Guest readiness when available",
    )


def check_host_proxy_runtime_state_read_is_vm_bootstrap_only() -> CheckResult:
    path = MACOS_RUNTIME / "Support/Packaging/proxy-run.template"
    text = read(path)
    required = [
        'state_file="${vm_home}/data/run/runtime-state.json"',
        "read_vm_ip()",
        "read_guest_http()",
        "waiting for VM runtime bootstrap",
        "waiting for VM runtime state",
        "upstream_ready()",
        "proxy_ready()",
    ]
    forbidden = [
        "containerServices",
        "composeServices",
        "recorderIngress",
        "redisRelay",
        "vitalDB",
        "serviceHealth",
        "serviceStatus",
        "Guest product services",
        "testkit",
        "TestKit",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if missing or present:
        return CheckResult(
            "host-proxy-runtime-state-bootstrap-only",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "host-proxy-runtime-state-bootstrap-only",
        True,
        "Host proxy reads runtime-state only for VM IP/bootstrap HTTP discovery, "
        "not product service state",
    )


def check_managed_operation_guard_does_not_read_runtime_state() -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeManagedOperationGuardComposition.swift"
    )
    text = read(path)
    required = [
        "lifecycle.bootID",
        "lifecycleBootID",
        "RuntimeVMLifecycleStore",
    ]
    forbidden = [
        "loadRuntimeStateDocument",
        "GuestRuntimeStateDocument",
        "runtimeState.bootID",
        "runtimeBootID",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if missing or present:
        return CheckResult(
            "managed-operation-guard-no-runtime-state-read",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "managed-operation-guard-no-runtime-state-read",
        True,
        "watchdog managed-operation guard uses VM lifecycle/bootstrap contracts "
        "instead of runtime-state reads",
    )


def check_guest_bootstrap_current_boot_uses_vm_lifecycle() -> CheckResult:
    evaluator_path = (
        MACOS_RUNTIME
        / "Sources/Domain/Policies/GuestBootstrapEvaluator.swift"
    )
    health_usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeHealth"
        / "EvaluateRuntimeHealthUseCase.swift"
    )
    evaluator = read(evaluator_path)
    health_usecase = read(health_usecase_path)
    required = {
        relative(evaluator_path): [
            "currentBootID: String?",
            "bootstrapBootID == currentBootID",
        ],
        relative(health_usecase_path): [
            "currentBootID: observation.vmLifecycle?.bootID",
        ],
    }
    texts = {
        relative(evaluator_path): evaluator,
        relative(health_usecase_path): health_usecase,
    }
    forbidden = {
        relative(evaluator_path): [
            "guestState: GuestRuntimeStateDocument?",
            "guestState?.bootID",
            "guestBootID",
        ],
        relative(health_usecase_path): [
            "loadedGuestRuntimeState",
            "guestState: observation.loadedGuestRuntimeState",
        ],
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    if missing or present:
        return CheckResult(
            "guest-bootstrap-current-boot-vm-lifecycle",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "guest-bootstrap-current-boot-vm-lifecycle",
        True,
        "Guest bootstrap current-boot checks use VM lifecycle bootID, not "
        "runtime-state bootID",
    )


def check_recorder_ingress_status_is_guest_control_only() -> CheckResult:
    removed_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Health"
            / "RuntimeRecorderIngressStatusReader.swift"
        ),
        (
            MACOS_RUNTIME
            / "Tests/OutboundAdaptersTests"
            / "RuntimeRecorderIngressStatusReaderTests.swift"
        ),
    ]
    existing = [relative(path) for path in removed_paths if path.exists()]
    scan_roots = [
        MACOS_RUNTIME / "Sources/Adapters/Outbound/MacRuntimeControlClient",
        MACOS_RUNTIME / "Sources/Adapters/Outbound/Health",
        MACOS_RUNTIME / "Sources/Contracts",
        MACOS_RUNTIME / "Sources/Hosts",
        MACOS_RUNTIME / "Sources/Bootstrap",
        MACOS_RUNTIME / "Tests/MacControlPanelHostTests",
        PWA / "src",
        ROOT / "docs/runtime/macos/runtime-control.openapi.json",
    ]
    forbidden = [
        "RuntimeRecorderIngressHTTPStatusReadProvider",
        "RuntimeRecorderIngressStatusReader(",
        "recorderIngressStatusURL",
        "skippedMissingProxyPort",
        "http://127.0.0.1:\\(proxyPort)/recorder-ingress/status",
    ]
    matches = find_tokens(scan_roots, forbidden)
    if existing or matches:
        return CheckResult(
            "recorder-ingress-status-guest-control-only",
            False,
            f"existing_paths={existing} matches={matches[:10]}",
        )
    return CheckResult(
        "recorder-ingress-status-guest-control-only",
        True,
        "Host recorder-ingress status reads go through Guest Control API only",
    )


def check_recorder_ingress_does_not_read_runtime_state_memory_guard(
) -> CheckResult:
    removed_paths = [
        (
            ROOT
            / "apps/vitalserver-recorder-ingress/src/adapters/outbound/file"
            / "runtime-state-memory-guard-reader.ts"
        ),
        (
            ROOT
            / "apps/vitalserver-recorder-ingress/tests/unit"
            / "runtime-state-memory-guard-reader.test.ts"
        ),
    ]
    existing = [relative(path) for path in removed_paths if path.exists()]
    scan_roots = [
        ROOT / "apps/vitalserver-recorder-ingress/src",
        ROOT / "apps/vitalserver-recorder-ingress/tests/unit",
        MACOS_RUNTIME / "Support/Guest/compose.yaml",
    ]
    forbidden = [
        "RECORDER_INGRESS_RUNTIME_STATE_PATH",
        "RECORDER_INGRESS_RUNTIME_STATE_MAX_AGE_MS",
        "runtime-state-memory-guard-reader",
        "runtimeStatePath",
        "containerServices",
        "/run/tirosh/runtime/runtime-state.json",
    ]
    matches = find_tokens(scan_roots, forbidden)
    if existing or matches:
        return CheckResult(
            "recorder-ingress-no-runtime-state-memory-guard",
            False,
            f"existing_paths={existing} matches={matches[:10]}",
        )
    return CheckResult(
        "recorder-ingress-no-runtime-state-memory-guard",
        True,
        "recorder-ingress no longer reads runtime-state.json as a replay "
        "memory guard input",
    )


def check_runtime_boot_smoke_uses_guest_control_stack_status() -> CheckResult:
    path = GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_boot_smoke.py"
    text = read(path)
    required = [
        "/v1/stack/status",
        "read_guest_control_stack_status",
        "observed_stack_services",
        "product-lab-recorder-flow",
        "LAB_REPLAY_SMOKE_VITAL_FILE",
        "/v1/lab/vital-files/replay",
        "prepare_lab_replay_smoke_vital_file",
        "replaySessionId",
        '"guest-control-api"',
    ]
    forbidden = [
        "observed_compose_services",
        "runtime state containerServices is missing or empty",
        "runtime state is missing compose services",
        "invalid_compose_service_uptime",
        "MAX_RUNTIME_SMOKE_SERVICE_UPTIME_SECONDS",
        "testkit-recorder-flow",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if missing or present:
        return CheckResult(
            "runtime-boot-smoke-guest-control-stack-status",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-boot-smoke-guest-control-stack-status",
        True,
        "runtime boot smoke validates service readiness and Lab replay through "
        "Guest Control API",
    )


def check_runtime_proof_acceptance_targets_are_explicit() -> CheckResult:
    makefile = ROOT / "Makefile"
    config = ROOT / "make/vm/config.mk"
    makefile_text = read(makefile)
    config_text = read(config)
    required_makefile = [
        "runtime/proof/smoke:",
        "runtime/proof/no-v1-service-state:",
        "runtime/proof/python-focused:",
        "runtime/proof/swift-focused:",
        "runtime/proof/http-e2e:",
        "runtime/proof/review:",
        "runtime/proof/acceptance:",
        "PYTEST_RUNNER ?=",
        "runtime/proof/python-focused:",
        "$(PYTEST_RUNNER) apps/vitalserver-lab/tests",
        "apps/vitalserver-lab/tests",
        "packages/vitalserver-guest-tools/tests/test_guest_control_api.py",
        "packages/vitalserver-devtools/tests/unit/test_macos_release_plans.py",
        "pwa/check",
        "pwa/test",
        "pwa/build",
        'swift test --package-path "$(VM_SWIFT_PACKAGE_DIR)"',
        '"$(VM_RUNTIME_PROOF_SWIFT_FOCUSED_FILTER)"',
        "runtime/e2e/smoke",
        "runtime/proof/smoke",
        "Run focused Python Runtime v2 product/package tests",
        "Run focused Swift Host-side Runtime v2 acceptance tests",
        "Run Runtime Control HTTP E2E smoke test",
        "Run static, Python, and PWA Runtime v2 review gates",
        "Run review, Swift focused, HTTP E2E, and VM smoke Runtime v2 gates",
    ]
    required_config = [
        "VM_RUNTIME_PROOF_SWIFT_FOCUSED_FILTER",
        "RuntimeControlContractsTests",
        "HTTPRuntimeGuestControlGatewayTests",
        "EvaluateRuntimeHealthUseCaseTests",
        "RuntimeSettingsReaderTests",
    ]
    missing_makefile = [
        token for token in required_makefile if token not in makefile_text
    ]
    missing_config = [token for token in required_config if token not in config_text]
    if missing_makefile or missing_config:
        return CheckResult(
            "runtime-proof-acceptance-targets",
            False,
            "missing_makefile="
            f"{missing_makefile} missing_config={missing_config}",
        )
    return CheckResult(
        "runtime-proof-acceptance-targets",
        True,
        "Runtime v2 review, Swift focused, HTTP E2E, and VM smoke "
        "acceptance targets are explicit",
    )


def find_tokens(paths: list[Path], tokens: list[str]) -> list[str]:
    matches: list[str] = []
    for path in paths:
        if path.is_dir():
            files = [candidate for candidate in path.rglob("*") if candidate.is_file()]
        else:
            files = [path]
        for file_path in files:
            if ".build" in file_path.parts or "node_modules" in file_path.parts:
                continue
            try:
                text = read(file_path)
            except UnicodeDecodeError:
                continue
            for line_number, line in enumerate(text.splitlines(), start=1):
                for token in tokens:
                    if token in line:
                        matches.append(f"{relative(file_path)}:{line_number}:{token}")
    return matches


def path_has_files(path: Path) -> bool:
    if path.is_file():
        return True
    if not path.is_dir():
        return False
    return any(candidate.is_file() for candidate in path.rglob("*"))


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def text_between(text: str, start: str, end: str) -> str:
    start_index = text.find(start)
    if start_index == -1:
        return ""
    end_index = text.find(end, start_index)
    if end_index == -1:
        return text[start_index:]
    return text[start_index:end_index]


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


if __name__ == "__main__":
    raise SystemExit(main())
