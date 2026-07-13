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
        check_platform_state_is_canonical_independent_resource(),
        check_platform_and_runtime_capabilities_have_separate_owners(),
        check_platform_and_runtime_namespaces_are_canonical(),
        check_runtime_status_reader_uses_guest_control(),
        check_command_worker_uses_guest_address_provider(),
        check_runtime_container_observation_does_not_expose_compose_services(),
        check_runtime_status_assembly_does_not_promote_runtime_state_services(),
        check_runtime_status_assembly_uses_live_host_service_liveness(),
        check_runtime_status_assembly_carries_explicit_installation_state(),
        check_runtime_status_surfaces_use_explicit_installation_state(),
        check_runtime_status_assembly_does_not_promote_status_http_snapshots(),
        check_runtime_status_read_issues_do_not_create_action_needed(),
        check_runtime_presentation_does_not_use_status_operation_progress(),
        check_operation_state_reader_does_not_copy_status_updated_at(),
        check_runtime_status_document_has_no_container_observation(),
        check_runtime_event_contract_has_no_container_observation(),
        check_runtime_event_factory_does_not_write_container_observation(),
        check_runtime_observed_events_do_not_read_status_document_previous_status(),
        check_runtime_status_document_does_not_own_progress_state(),
        check_runtime_progress_document_failure_does_not_own_current_status_issue(),
        check_runtime_progress_artifact_sink_is_write_only(),
        check_runtime_status_artifact_sink_is_write_only(),
        check_runtime_diagnostics_artifact_file_names_are_separate(),
        check_runtime_current_owner_file_names_are_separate(),
        check_runtime_log_artifact_file_names_are_separate(),
        check_runtime_generic_file_names_are_removed(),
        check_runtime_settings_paths_use_installed_paths_defaults(),
        check_runtime_workflow_state_artifact_writers_are_named_as_artifacts(),
        check_runtime_status_document_does_not_own_current_health_state(),
        check_runtime_status_document_failure_reasons_are_not_current_health(),
        check_runtime_status_document_does_not_own_active_operation_state(),
        check_runtime_data_restore_does_not_restore_runtime_status_projection(),
        check_host_failure_reasons_do_not_model_container_observation_reads(),
        check_runtime_state_document_has_no_container_services(),
        check_runtime_state_document_has_no_capabilities(),
        check_runtime_guest_runtime_state_policy_is_removed(),
        check_runtime_guest_file_gateway_is_maintenance_only(),
        check_legacy_guest_request_result_file_names_are_removed(),
        check_swift_legacy_guest_result_documents_are_removed(),
        check_guest_request_file_poller_is_removed(),
        check_redis_backup_file_bridge_is_absent_from_runtime_observation_writer(),
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
        check_runtime_command_result_preserves_explicit_execution_evidence(),
        check_product_surfaces_do_not_expose_dev_testkit(),
        check_runtime_control_api_exposes_v2_product_surface(),
        check_guest_control_lab_boundary_does_not_name_testkit(),
        check_guest_control_default_state_uses_sqlite_control_store(),
        check_guest_service_operations_persist_status_snapshots(),
        check_guest_service_control_is_controller_owned_resource(),
        check_runtime_config_does_not_enable_testkit(),
        check_product_packaging_uses_lab_not_testkit(),
        check_vitaldb_read_models_do_not_name_host_sqlite_as_source(),
        check_vitaldb_observation_snapshot_preserves_explicit_read_state_contract(),
        check_vitaldb_relationship_history_preserves_explicit_read_state_contract(),
        check_vitaldb_beds_use_explicit_bed_read_document(),
        check_vitaldb_host_sqlite_projection_requires_diagnostics_mode(),
        check_runtime_event_sqlite_index_failure_does_not_fail_primary_append(),
        check_host_does_not_write_vitaldb_sqlite_projection(),
        check_host_health_does_not_promote_vitaldb_read_model_failures(),
        check_host_health_uses_guest_control_ready_for_guest_readiness(),
        check_host_proxy_runtime_state_read_is_vm_bootstrap_only(),
        check_devtools_runtime_wait_uses_bootstrap_address_and_http_probe(),
        check_devtools_runtime_health_uses_bootstrap_address_and_http_probe(),
        check_dev_make_proxy_start_uses_guest_address_owner(),
        check_current_health_has_no_reported_vm_error_input(),
        check_managed_operation_guard_does_not_read_runtime_state(),
        check_cli_host_centralizes_operation_lease_owner_adapter_selection(),
        check_host_guest_address_has_runtime_control_api_owner_surface(),
        check_host_vm_lifecycle_has_runtime_control_api_owner_surface(),
        check_guest_bootstrap_result_is_not_current_state_input(),
        check_health_recovery_policies_do_not_accept_diagnostics_observations(),
        check_health_snapshot_contract_does_not_carry_container_observation(),
        check_runtime_status_document_does_not_store_vitaldb_observation(),
        check_runtime_status_contract_has_no_vitaldb_observation(),
        check_recorder_ingress_status_read_result_preserves_explicit_read_contract(),
        check_redis_relay_status_document_preserves_complete_owner_contract(),
        check_redis_relay_status_read_result_preserves_explicit_read_contract(),
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
        check_cli_guest_control_default_url_uses_guest_address_provider(),
        check_product_readmes_do_not_promote_legacy_sources(),
        check_testkit_package_is_dev_tooling_only(),
        check_runtime_proof_local_artifacts_and_private_samples_are_ignored(),
        check_product_docs_do_not_promote_testkit_runtime_surface(),
        check_runtime_proof_docs_describe_acceptance_targets(),
        check_delivery_validation_docs_do_not_promote_legacy_runtime_state_files(),
        check_runtime_update_docs_do_not_promote_status_files_as_current_owners(),
        check_runtime_event_history_docs_do_not_promote_files_as_state_owners(),
        check_api_catalog_exposes_runtime_support_specs(),
        check_runtime_proof_troubleshooting_documents_acceptance_blockers(),
        check_maintenance_docs_do_not_promote_request_files_as_current_path(),
        check_observer_docs_use_guest_postgres_read_model_flow(),
        check_redis_relay_status_docs_use_guest_control_api_flow(),
        check_native_control_panel_redis_relay_settings_are_runtime_owned(),
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


def check_platform_state_is_canonical_independent_resource() -> CheckResult:
    endpoint_routing = read(
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpointRouting.swift"
    )
    swift_models = read(
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlModels.swift"
    )
    swift_overview = read(
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlReadModels.swift"
    )
    overview_block = text_between(
        swift_overview,
        "public struct RuntimeControlOverview:",
        "private static func vitalDBObservationCondition",
    )
    pwa_schemas = read(
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    pwa_client = read(
        PWA / "src/infrastructure/console-api/runtimeControlApiClient.ts"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    openapi = json.loads(read(openapi_path))
    paths = openapi.get("paths", {})
    schemas = openapi.get("components", {}).get("schemas", {})
    overview_properties = schemas.get("RuntimeControlOverview", {}).get("properties", {})
    platform_properties = schemas.get("PlatformState", {}).get("properties", {})

    missing: list[str] = []
    for token in [
        'path: "/platform"',
        'path: "/platform/stream"',
        "case .platformState:",
        "case .platformStateStream:",
    ]:
        if token not in endpoint_routing:
            missing.append(f"routing:{token}")
    for token in [
        "public struct PlatformState:",
        "export const platformStateSchema = z",
    ]:
        source = swift_models if token.startswith("public struct") else pwa_schemas
        if token not in source:
            missing.append(token)
    if 'return this.get("/platform", platformStateSchema);' not in pwa_client:
        missing.append("PWA:PlatformState independent /platform read")
    if "/platform" not in paths or "/platform/stream" not in paths:
        missing.append("OpenAPI:/platform resources")
    if "PlatformState" not in schemas:
        missing.append("OpenAPI:PlatformState")

    forbidden: list[str] = []
    if 'path: "/runtime/status"' in endpoint_routing:
        forbidden.append("routing:/runtime/status")
    if "/runtime/status" in paths:
        forbidden.append("OpenAPI:/runtime/status")
    if "RuntimeStatus" in schemas:
        forbidden.append("OpenAPI:RuntimeStatus")
    if "public struct RuntimeStatus:" in swift_models:
        forbidden.append("Swift:RuntimeStatus")
    if "public let status: PlatformState" in overview_block:
        forbidden.append("Swift overview embeds PlatformState")
    if "status" in overview_properties:
        forbidden.append("OpenAPI overview embeds PlatformState")

    canonical_platform_fields = {
        "runtimeInstallationState",
        "services",
        "platformHealth",
        "readIssues",
        "installedVersion",
        "latestBackup",
        "runtimeProviderState",
        "runtimeProviderErrors",
        "runtimeEndpoint",
        "runtimeControllerHTTP",
        "publicProxyHTTP",
        "platformAPIHTTP",
        "platformAPIStartedAt",
        "dataStorage",
        "dataStorageError",
        "dataDirectoryStats",
        "dataDirectoryStatsError",
        "publicProxyPort",
        "publicProxyPortReadState",
        "healthIssues",
    }
    if set(platform_properties) != canonical_platform_fields:
        missing.append(
            "OpenAPI:PlatformState canonical fields "
            f"actual={sorted(platform_properties)}"
        )
    platform_services = platform_properties.get("services", {})
    expected_platform_service_roles = {
        "runtime-provider",
        "public-proxy",
        "log-sync",
        "sleep-prevention",
        "watchdog",
    }
    service_role_constraints = platform_services.get("allOf", [])
    constrained_roles = {
        clause.get("contains", {})
        .get("properties", {})
        .get("role", {})
        .get("const")
        for clause in service_role_constraints
        if isinstance(clause, dict)
    }
    if (
        platform_services.get("minItems") != len(expected_platform_service_roles)
        or platform_services.get("maxItems") != len(expected_platform_service_roles)
        or constrained_roles != expected_platform_service_roles
        or any(
            clause.get("minContains") != 1 or clause.get("maxContains") != 1
            for clause in service_role_constraints
            if isinstance(clause, dict)
        )
    ):
        missing.append(
            "OpenAPI:PlatformState services require each fixed role exactly once"
        )
    for token in [
        "case platformHealth",
        "case runtimeProviderState",
        "case runtimeEndpoint",
        "case platformAPIHTTP",
        "case publicProxyPort",
        "case healthIssues",
    ]:
        if token not in swift_models:
            missing.append(f"Swift:{token}")
    for token in [
        "platformHealth: runtimeStateSchema.optional()",
        "runtimeProviderState: vmStateSchema.optional()",
        "runtimeEndpoint: nullableString",
        "platformAPIHTTP: nullableString",
        "publicProxyPort: z.number().optional()",
        "healthIssues: z.array(z.string()).optional()",
        "platformServiceRoleValues",
        "Platform service role must be reported exactly once",
        "Platform service role is required",
    ]:
        if token not in pwa_schemas:
            missing.append(f"PWA:{token}")

    if missing or forbidden:
        return CheckResult(
            "platform-state-canonical-independent-resource",
            False,
            f"missing={missing} forbidden={forbidden}",
        )
    return CheckResult(
        "platform-state-canonical-independent-resource",
        True,
        "PlatformState uses the canonical cross-platform vocabulary, is served only from /platform, and is not embedded in Runtime overview",
    )


def check_platform_and_runtime_capabilities_have_separate_owners() -> CheckResult:
    routing = read(
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpointRouting.swift"
    )
    handler = read(
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlClientAPIReadHandler.swift"
    )
    pwa_client = read(
        PWA / "src/infrastructure/console-api/runtimeControlApiClient.ts"
    )
    openapi = json.loads(
        read(ROOT / "docs/runtime/runtime-control.openapi.json")
    )
    paths = openapi.get("paths", {})
    schemas = openapi.get("components", {}).get("schemas", {})
    platform_schema = schemas.get("PlatformCapabilities", {})
    runtime_schema = schemas.get("RuntimeCapabilities", {})

    missing = [
        token
        for token, text in [
            ('path: "/platform/capabilities"', routing),
            ('path: "/runtime/capabilities"', routing),
            ("PlatformCapabilities(client.capabilities)", handler),
            ("try await client.runtimeCapabilities()", handler),
            ("this.getPlatformCapabilities()", pwa_client),
            ("this.getRuntimeCapabilities()", pwa_client),
            ('available.has("services:start")', pwa_client),
            ('available.has("lab:scenarios")', pwa_client),
        ]
        if token not in text
    ]
    if "/platform/capabilities" not in paths:
        missing.append("OpenAPI:/platform/capabilities")
    if "/runtime/capabilities" not in paths:
        missing.append("OpenAPI:/runtime/capabilities")

    issues: list[str] = []
    if platform_schema.get("additionalProperties") is not False:
        issues.append("PlatformCapabilities must be closed")
    platform_properties = set(platform_schema.get("properties", {}))
    if platform_properties != set(platform_schema.get("required", [])):
        issues.append("PlatformCapabilities properties must all be required")
    if {"canControlGuestServices", "canUseLab"} & platform_properties:
        issues.append("PlatformCapabilities carries Runtime product capability")
    if "canEditVMResources" in platform_properties:
        issues.append("PlatformCapabilities carries VM-specific vocabulary")
    if "canEditRuntimeProviderResources" not in platform_properties:
        issues.append("PlatformCapabilities misses runtime-provider resource capability")
    if runtime_schema.get("additionalProperties") is not False:
        issues.append("RuntimeCapabilities must be closed")
    if set(runtime_schema.get("required", [])) != {"schemaVersion", "capabilities"}:
        issues.append("RuntimeCapabilities must require owner version and identifiers")
    if "RuntimeControlCapabilities" in schemas:
        issues.append("legacy mixed OpenAPI capability schema remains")

    if missing or issues:
        return CheckResult(
            "platform-runtime-capability-owner-split",
            False,
            f"missing={missing} issues={issues}",
        )
    return CheckResult(
        "platform-runtime-capability-owner-split",
        True,
        "Platform and Runtime capability resources are independent owner contracts",
    )


def check_platform_and_runtime_namespaces_are_canonical() -> CheckResult:
    endpoint_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpointRouting.swift"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    pwa_client_path = PWA / "src/infrastructure/console-api/runtimeControlApiClient.ts"
    texts = {
        relative(endpoint_path): read(endpoint_path),
        relative(openapi_path): read(openapi_path),
        relative(pwa_client_path): read(pwa_client_path),
    }
    required = [
        "/platform/runtime-provider",
        "/platform/uninstall",
        "/platform/update-bundles",
        "/platform/backups",
        "/runtime/lab/",
        "/runtime/vitaldb/",
        "/runtime/maintenance/datastore/repair",
    ]
    missing = {
        path: [token for token in required if token not in text]
        for path, text in texts.items()
        if any(token not in text for token in required)
    }
    endpoint_and_openapi = [relative(endpoint_path), relative(openapi_path)]
    for path in endpoint_and_openapi:
        for token in [
            "/platform/runtime-endpoint",
            "/platform/operations",
            "/platform/operations/lease",
            "/platform/installation",
        ]:
            if token not in texts[path]:
                missing.setdefault(path, []).append(token)
    for path in endpoint_and_openapi:
        if "/runtime/services/{service}" not in texts[path]:
            missing.setdefault(path, []).append("/runtime/services/{service}")
    if "/runtime/services/${encodeURIComponent(request.service)}" not in texts[relative(pwa_client_path)]:
        missing.setdefault(relative(pwa_client_path), []).append(
            "/runtime/services/${encodeURIComponent(request.service)}"
        )
    legacy = [
        "/host/",
        "/runtime/guest/",
        '"/lab/',
        '"/vitaldb/',
        "/runtime/install",
        "/runtime/uninstall",
        "/runtime/services/repair-proxy",
        "/runtime/services/repair-vm-disk",
        "/platform/operation-state",
    ]
    present = [
        f"{path}:{token}"
        for path, text in texts.items()
        for token in legacy
        if token in text
    ]
    openapi = json.loads(texts[relative(openapi_path)])
    schemas = openapi.get("components", {}).get("schemas", {})
    if "PlatformOperationState" not in schemas:
        missing.setdefault(relative(openapi_path), []).append("PlatformOperationState")
    if "RuntimeOperationState" in schemas:
        present.append(f"{relative(openapi_path)}:RuntimeOperationState")
    for schema_name in [
        "RuntimeProviderState",
        "RuntimeProviderError",
        "RuntimeEndpointResourceState",
        "RuntimeEndpointReadResult",
        "RuntimeProviderResourceState",
        "RuntimeProviderLifecycleDocument",
    ]:
        if schema_name not in schemas:
            missing.setdefault(relative(openapi_path), []).append(schema_name)
    for legacy_schema in [
        "RuntimeVMState",
        "RuntimeVMError",
        "RuntimeGuestAddressResourceState",
        "RuntimeGuestAddressReadResult",
        "RuntimeVMLifecycleResourceState",
        "RuntimeVMLifecycleDocument",
    ]:
        if legacy_schema in schemas:
            present.append(f"{relative(openapi_path)}:{legacy_schema}")
    if missing or present:
        return CheckResult(
            "platform-runtime-canonical-namespaces",
            False,
            f"missing={missing} legacy={present[:20]}",
        )
    return CheckResult(
        "platform-runtime-canonical-namespaces",
        True,
        "Platform and Runtime API paths use owner namespaces without compatibility aliases",
    )


def check_runtime_status_reader_uses_guest_control() -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeStatusReader.swift"
    )
    runtime_paths_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Environment"
        / "RuntimePaths.swift"
    )
    text = read(path)
    required = [
        "guestAddressProvider = guestAddressProvider ?? ownerReaders.guestAddressProvider",
        "guestAddressProvider.readGuestAddress()",
        "RuntimeHostStatusOwnerReaderBundle.live(",
        "vmLifecycleReader.loadVMLifecycleRead()",
        "vmLifecycleRead: vmLifecycleRead",
        "RuntimePackageArtifactFileNames.runtimeVersion",
        "InstalledRuntimePaths.defaultInstalled.backupsDirectory",
    ]
    forbidden = [
        "containerServices",
        "composeServices",
        "service-stack-status",
        "serviceStackStatus",
        "runtime-observation.json",
        "GuestRuntimeObservationDocumentReader",
        "paths.runtimeObservation",
        "RuntimeStatusDocumentReader(",
        "paths.runtimeStatus",
        "RuntimeRedisRelayStatusReader(",
        "redisRelayStatusRead(",
        ".redisRelayStatus()",
        "paths.redisRelayStatus",
        "RuntimeInstallStateDocumentReader(",
        "paths.runtimeInstallState",
        "RuntimeVersionStore(",
        "RuntimeProxyLaunchDaemonPortReader(",
        "RuntimeVMLifecycleStore(",
        "RuntimeManagedBackupPolicy.nameFragment",
        "paths.runtimeVersion",
        "paths.backupsDirectory",
        "paths.proxyLaunchDaemon",
        "paths.vmLifecycle",
        "paths.vmIPFile",
        "RuntimeControlClientConstants.Paths.runtimeVersion",
        "RuntimeControlClientConstants.Paths.backups",
        "RuntimeVMIPFileGuestAddressProvider(",
        "installStateRead:",
        "statusRead:",
        "statusRead.document?.vmIP",
        "statusRead.document?.vmState",
        "statusRead.document?.vmErrors",
        "gateway.stackStatus()",
        "gateway.serviceResource(",
        "RuntimeGuestServicesRead",
        "guestServiceResourcesRead(",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    owner_readers_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeHostStatusOwnerReaders.swift"
    )
    owner_readers_text = read(owner_readers_path)
    owner_required = [
        "proxyPortReader: RuntimeHostProxyPortReader(",
        "plistPath: InstalledRuntimePaths.defaultInstalled.proxyLaunchDaemon.path",
        "RuntimePackageArtifactFileNames.runtimeVersion",
        "InstalledRuntimePaths.defaultInstalled.backupsDirectory",
        "RuntimeProxyLaunchDaemonPortReader(",
        "backup directory missing path=\\(backupsDirectory.path)",
    ]
    missing += [
        f"{relative(owner_readers_path)}:{token}"
        for token in owner_required
        if token not in owner_readers_text
    ]
    owner_forbidden = [
        "RuntimeProxyPortOwnerReader.live(",
        "RuntimeControlClientConstants.Paths.proxyLaunchDaemon",
        "RuntimeControlClientConstants.Paths.runtimeVersion",
        "RuntimeControlClientConstants.Paths.backups",
        "case .missing:\n            return RuntimeLatestBackupRead(path: nil, issue: nil)",
    ]
    present += [
        f"{relative(owner_readers_path)}:{token}"
        for token in owner_forbidden
        if token in owner_readers_text
    ]
    proxy_owner_wrapper_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Environment"
        / "RuntimeProxyPortOwnerReader.swift"
    )
    if proxy_owner_wrapper_path.exists():
        present.append(
            f"{relative(proxy_owner_wrapper_path)}:ambiguous proxy port owner wrapper must be removed"
        )
    if runtime_paths_path.exists():
        present.append(f"{relative(runtime_paths_path)}:broad RuntimePaths file must be removed")
    if missing or present:
        return CheckResult(
            "runtime-status-reader-no-product-stack-aggregation",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-status-reader-no-product-stack-aggregation",
        True,
        "Host RuntimeStatus reader does not aggregate product stack or controller resources "
        f"path={relative(path)}",
    )


def check_command_worker_uses_guest_address_provider() -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
        / "MacRuntimeControlCommandWorker.swift"
    )
    text = read(path)
    required = [
        "private let guestAddressProvider",
        "self.guestAddressProvider = guestAddressProvider",
        "guestAddressProvider.readGuestAddress()",
        "guestAddressRead.loadedAddress",
    ]
    forbidden = [
        "RuntimeVMIPFileGuestAddressProvider(",
        "RuntimeStatusDocumentReader(",
        "read.document?.vmIP",
        "read.document?.guestAddressRead",
        "runtime status document does not report vmIP",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if missing or present:
        return CheckResult(
            "command-worker-guest-address-provider",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "command-worker-guest-address-provider",
        True,
        "Host command worker derives Guest Control base URL from explicit Guest address reads",
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
        ROOT / "docs/runtime/runtime-control.openapi.json",
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
        "GuestRuntimeObservationRead",
        "GuestRuntimeObservationDocument",
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


def check_runtime_status_assembly_uses_live_host_service_liveness() -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift"
    )
    text = read(path)
    models_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlModels.swift"
    )
    models_text = read(models_path)
    required = [
        "let vmService = liveServiceState(liveServiceStates.vm)",
        "let proxyService = liveServiceState(liveServiceStates.proxy)",
        "let watchdogService = liveServiceState(liveServiceStates.watchdog)",
    ]
    forbidden = [
        "statusDocument _: RuntimeStatusDocument?",
        "document?.vmService",
        "document?.proxyService",
        "document?.watchdogService",
        "source: .statusDocument",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    model_forbidden = [
        'case statusDocument = "status-document"',
    ]
    present += [
        f"{relative(models_path)}:{token}"
        for token in model_forbidden
        if token in models_text
    ]
    if missing or present:
        return CheckResult(
            "runtime-status-assembly-live-host-service-liveness",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-status-assembly-live-host-service-liveness",
        True,
        "Host managed service liveness is assembled from live host reads, not runtime-status.json "
        f"path={relative(path)}",
    )


def check_runtime_status_assembly_carries_explicit_installation_state() -> CheckResult:
    assembly_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift"
    )
    models_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlModels.swift"
    )
    assembly_text = read(assembly_path)
    models_text = read(models_path)
    required = [
        "runtimeInstallationState: RuntimeFileState",
        "runtimeInstallationState: runtimeExecutableState",
        "runtimeInstallationState: liveDiagnostics.runtimeInstallationState",
    ]
    forbidden = [
        "runtimeInstallationState: nil",
        "runtimeInstallationState: liveDiagnostics.runtimeInstalled",
        "runtimeInstallationState: status.runtimeInstalled",
    ]
    missing = [token for token in required if token not in assembly_text]
    present = [token for token in forbidden if token in assembly_text]
    model_required = [
            "public var runtimeInstallationState: RuntimeFileState",
    ]
    model_forbidden = [
        "public var effectiveRuntimeInstallationState",
        "runtimeInstallationState ?? (runtimeInstalled ? .executable : .missing)",
    ]
    model_missing = [
        f"{relative(models_path)}:{token}"
        for token in model_required
        if token not in models_text
    ]
    present += [
        f"{relative(models_path)}:{token}"
        for token in model_forbidden
        if token in models_text
    ]
    if missing or present or model_missing:
        return CheckResult(
            "runtime-status-explicit-installation-state",
            False,
            (
                f"missing={missing} model_missing={model_missing} "
                f"forbidden_present={present} path={relative(assembly_path)}"
            ),
        )
    return CheckResult(
        "runtime-status-explicit-installation-state",
        True,
        "RuntimeStatus production assembly carries explicit runtime installation file state",
    )


def check_runtime_status_surfaces_use_explicit_installation_state() -> CheckResult:
    paths = {
        relative(
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/RuntimeControlAPI/DevConsole/RuntimeControlDevConsole.html"
        ): read(
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/RuntimeControlAPI/DevConsole/RuntimeControlDevConsole.html"
        ),
        relative(
            PWA / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
        ): read(PWA / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"),
        relative(
            PWA / "src/domain/runtime-control/contracts/generated/runtime-control.ts"
        ): read(PWA / "src/domain/runtime-control/contracts/generated/runtime-control.ts"),
        relative(PWA / "src/pages/advanced/AdvancedPage.tsx"): read(
            PWA / "src/pages/advanced/AdvancedPage.tsx"
        ),
        relative(ROOT / "docs/runtime/runtime-control.openapi.json"): read(
            ROOT / "docs/runtime/runtime-control.openapi.json"
        ),
        relative(ROOT / "docs/runtime/macos/runtime-control-api.md"): read(
            ROOT / "docs/runtime/macos/runtime-control-api.md"
        ),
    }
    required = [
        (
            "apps/vitalserver-macos-runtime/Sources/Adapters/Inbound/RuntimeControlAPI/DevConsole/RuntimeControlDevConsole.html",
            "status.runtimeInstallationState === \"executable\"",
        ),
        (
            "apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts",
            "runtimeInstallationState: z.string()",
        ),
        (
            "apps/vitalserver-runtime-pwa/src/domain/runtime-control/contracts/generated/runtime-control.ts",
            "runtimeInstallationState: string",
        ),
        (
            "apps/vitalserver-runtime-pwa/src/pages/advanced/AdvancedPage.tsx",
            "const runtimeInstallationState = status?.runtimeInstallationState",
        ),
        (
            "docs/runtime/runtime-control.openapi.json",
            "\"runtimeInstallationState\"",
        ),
        (
            "docs/runtime/runtime-control.openapi.json",
            "Explicit Platform Agent runtime installation state.",
        ),
        (
            "docs/runtime/macos/runtime-control-api.md",
            "`RuntimeStatus.runtimeInstallationState`",
        ),
        (
            "docs/runtime/macos/runtime-control-api.md",
            "`runtimeInstalled`는 호환/display hint로만 남으며 설치 상태의 source of truth가 아닙니다.",
        ),
    ]
    forbidden = [
        (
            "apps/vitalserver-macos-runtime/Sources/Adapters/Inbound/RuntimeControlAPI/DevConsole/RuntimeControlDevConsole.html",
            "!status.runtimeInstalled",
        ),
        (
            "apps/vitalserver-runtime-pwa/src/pages/advanced/AdvancedPage.tsx",
            "const runtimeInstalled = status?.runtimeInstalled",
        ),
        (
            "docs/runtime/macos/runtime-control-api.md",
            "| Runtime installation | `RuntimeStatus.runtimeInstalled`",
        ),
    ]
    missing = [
        f"{path}:{token}"
        for path, token in required
        if token not in paths[path]
    ]
    present = [
        f"{path}:{token}"
        for path, token in forbidden
        if token in paths[path]
    ]
    if missing or present:
        return CheckResult(
            "runtime-status-surfaces-explicit-installation-state",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "runtime-status-surfaces-explicit-installation-state",
        True,
        "Runtime Control API, PWA, DevConsole, and docs use explicit runtimeInstallationState",
    )


def check_runtime_status_assembly_does_not_promote_status_http_snapshots(
) -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift"
    )
    text = read(path)
    forbidden = [
        "guestHTTP: document?.guestHTTP",
        "hostProxyHTTP: document?.hostProxyHTTP",
        "redisUIHTTP: document?.redisUIHTTP",
        "swaggerUIHTTP: document?.swaggerUIHTTP",
        "vmIP: document?.vmIP",
        "vmState: document?.vmState",
        "vmErrors: document?.vmErrors",
        "proxyPort: document?.proxyPort",
        "proxyPortReadState: document?.proxyPortReadState",
        "runtimeVersion: document?.runtimeVersion",
        "latestBackup: document?.latestBackup",
        "runtimeState: document.map",
        "failureReasons: document?.failureReasons",
        "operation: document?.operation",
        "statusMessage: document?.message",
        "updatedAt: document?.updatedAt",
        "progress: document?.progress",
        "statusRead.issue",
        "guestAddressReadIssue",
        'source: "guestAddress"',
        ".guestHTTP(guestAddressRead.failureStatusText)",
        "proxyPortReadIssue",
        "proxyPortReadState?.failureReasons",
        'source: "vmIP"',
        'source: "proxyPort"',
        "!failureReasons.isEmpty || !readIssues.isEmpty",
        "RuntimeActiveOperationRead",
        "RuntimeProgressRead",
        "activeOperationRead: RuntimeActiveOperationRead",
        "progressRead: RuntimeProgressRead",
        "RuntimeInstallStateRead",
        "operation: activeOperationRead.document?.operation",
        "statusMessage: activeOperationRead.document?.message",
        "updatedAt: activeOperationRead.document?.heartbeatAt",
        "startedAt: activeOperationRead.document?.startedAt",
        "progress: progressRead.document",
        "statusDocumentError: statusRead.error",
        "installStateRead:",
        "installStateRead.document",
        "installStateRead.error",
    ]
    required = [
        "RuntimeVMLifecycleRead",
        "RuntimeCurrentHealthRead",
        "proxyPortReadState: RuntimeProxyPortReadState?",
        "runtimeVersionRead: RuntimeVersionRead",
        "latestBackupRead: RuntimeLatestBackupRead",
        "vmLifecycleRead.issue",
        "vmState(from: vmLifecycleRead.document)",
        "runtimeProviderErrors: vmLifecycleRead.document?.reportedVMErrors",
        "runtimeEndpoint: guestAddressRead.loadedAddress",
        "isCurrentRuntimeStateReadIssue",
        "readIssues.contains(where: isCurrentRuntimeStateReadIssue)",
        "currentHealthRead: RuntimeCurrentHealthRead?",
        "platformHealth: currentHealth.runtimeState",
        "healthIssues: currentHealth.failureReasons",
        "publicProxyPort: proxyPortReadState?.port",
        "installedVersion: runtimeVersionRead.version",
        "latestBackup: latestBackupRead.path",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    current_runtime_issue_sources = text_between(
        text,
        "private static func isCurrentRuntimeStateReadIssue",
        "private static func currentFailureReasons",
    )
    if '"activeOperation"' in current_runtime_issue_sources:
        present.append(
            "activeOperation current runtime-state read issue source"
        )
    for diagnostics_only_source in ['"runtimeVersion"', '"latestBackup"']:
        if diagnostics_only_source in current_runtime_issue_sources:
            present.append(
                f"{diagnostics_only_source} current runtime-state read issue source"
            )
    current_failure_reasons = text_between(
        text,
        "private static func currentFailureReasons",
        "private static func appendServiceReason",
    )
    for diagnostics_only_input in [
        "runtimeVersionRead",
        "latestBackupRead",
        "runtimeVersionRead.issue",
        "latestBackupRead.issue",
    ]:
        if diagnostics_only_input in current_failure_reasons:
            present.append(
                f"{diagnostics_only_input} current failure reason input"
            )
    proxy_port_read_state_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeProxyPortReadState.swift"
    )
    proxy_port_read_state_text = read(proxy_port_read_state_path)
    if "failureReasons" in proxy_port_read_state_text:
        present.append(
            f"RuntimeProxyPortReadState.failureReasons path={relative(proxy_port_read_state_path)}"
        )
    if missing or present:
        return CheckResult(
            "runtime-status-assembly-no-status-http-snapshots",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-status-assembly-no-status-http-snapshots",
        True,
        "RuntimeStatus current health, HTTP, VM IP, VM lifecycle, proxy port, version, and backup fields come from "
        "explicit owner reads, while active operation and progress stay out of RuntimeStatus",
    )


def check_runtime_status_read_issues_do_not_create_action_needed() -> CheckResult:
    action_needed_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies"
        / "RuntimeStatusActionNeededPolicy.swift"
    )
    health_details_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies"
        / "RuntimeStatusHealthDetailsPolicy.swift"
    )
    advanced_vm_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies"
        / "RuntimeStatusAdvancedVMHealthPolicy.swift"
    )
    overall_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies"
        / "RuntimeStatusOverallHealthPolicy.swift"
    )
    texts = {
        relative(action_needed_path): read(action_needed_path),
        relative(health_details_path): read(health_details_path),
        relative(advanced_vm_path): read(advanced_vm_path),
        relative(overall_path): read(overall_path),
    }
    forbidden_by_path = {
        relative(action_needed_path): [
            "if !status.readIssues.isEmpty",
            'RuntimeFileState.unknown("runtime-installation-state-unavailable")',
        ],
        relative(health_details_path): [
            'RuntimeFileState.unknown("runtime-installation-state-unavailable")',
        ],
        relative(advanced_vm_path): [
            'RuntimeFileState.unknown("runtime-installation-state-unavailable")',
        ],
        relative(overall_path): [
            'RuntimeFileState.unknown("runtime-installation-state-unavailable")',
        ],
    }
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden_by_path.items()
        for token in tokens
        if token in texts[path]
    ]
    if present:
        return CheckResult(
            "runtime-status-read-issues-no-action-needed",
            False,
            f"forbidden_present={present}",
        )
    return CheckResult(
        "runtime-status-read-issues-no-action-needed",
        True,
        "RuntimeStatus read issues and missing owner fields remain diagnostics and do not create action-needed state",
    )


def check_runtime_presentation_does_not_use_status_operation_progress(
) -> CheckResult:
    checked = {
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Formatting"
        / "RuntimePresentationFormatter.swift": [
            "status.progress",
            "status.statusMessage",
        ],
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Refresh"
        / "RuntimeStatusRefresher.swift": [
            "progressDisplayMessage",
            "synchronizeFileBackedOperation",
            "fileBackedOperation",
        ],
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/DevConsole"
        / "RuntimeControlDevConsole.html": [
            "status.operation",
            "status.statusMessage",
            "status.startedAt",
            "status.updatedAt",
        ],
    }
    present = [
        (relative(path), token)
        for path, forbidden in checked.items()
        for token in forbidden
        if token in read(path)
    ]
    if present:
        return CheckResult(
            "runtime-presentation-no-status-operation-progress",
            False,
            f"forbidden_present={present}",
        )
    refresher_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Refresh"
        / "RuntimeStatusRefresher.swift"
    )
    refresher_text = read(refresher_path)
    if "includeOperationStatePresentation" not in refresher_text:
        return CheckResult(
            "runtime-presentation-no-status-operation-progress",
            False,
            "RuntimeStatusRefresher must present operations from explicit PlatformOperationState",
        )
    return CheckResult(
        "runtime-presentation-no-status-operation-progress",
        True,
        "Runtime presentation surfaces do not use RuntimeStatus operation/progress fields",
    )


def check_operation_state_reader_does_not_copy_status_updated_at() -> CheckResult:
    read_worker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "MacRuntimeControlReadWorker.swift"
    )
    operation_resource_reader_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "PlatformOperationStateResourceReader.swift"
    )
    status_document_readers_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeStatusDocumentReaders.swift"
    )
    mac_runtime_environment_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent"
        / "MacPlatformAgentService.swift"
    )
    swift_read_models_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl"
        / "RuntimeControlReadModels.swift"
    )
    swift_client_contract_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl"
        / "RuntimeClientContracts.swift"
    )
    api_read_handler_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlClientAPIReadHandler.swift"
    )
    http_read_routes_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlHTTPReadRoutes.swift"
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
    swift_contract_tests_path = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    checked = [
        read_worker_path,
        operation_resource_reader_path,
        swift_read_models_path,
        swift_client_contract_path,
        api_read_handler_path,
        http_read_routes_path,
        pwa_schema_path,
        pwa_generated_path,
        openapi_path,
    ]
    present = [
        f"{relative(path)}:runtimeStatusUpdatedAt"
        for path in checked
        if "runtimeStatusUpdatedAt" in read(path)
    ]
    if status_document_readers_path.exists():
        present.append(
            f"{relative(status_document_readers_path)}:status document reader adapter must be removed"
        )
    read_worker_text = read(read_worker_path)
    operation_resource_reader_text = read(operation_resource_reader_path)
    mac_runtime_environment_text = read(mac_runtime_environment_path)
    read_models_text = read(swift_read_models_path)
    client_contract_text = read(swift_client_contract_path)
    swift_contract_tests_text = read(swift_contract_tests_path)
    api_read_handler_text = read(api_read_handler_path)
    http_read_routes_text = read(http_read_routes_path)
    required = [
        (
            relative(read_worker_path),
            "any PlatformOperationStateResourceReading",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "RuntimeInstallOperationState.fromInstallStateRead",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "resourceReader.loadResourceSnapshot()",
            read_worker_text,
        ),
        (
            relative(operation_resource_reader_path),
            "struct PlatformOperationStateResourceSnapshot",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "func loadResourceSnapshot() -> PlatformOperationStateResourceSnapshot",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "struct HostPlatformOperationStateResourceReader",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "RuntimeInstallStateRead.unavailable()",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "any RuntimeOperationLeaseReading",
            operation_resource_reader_text,
        ),
        (
            relative(mac_runtime_environment_path),
            "let operationLeaseController = RuntimeControlOperationLeaseController(",
            mac_runtime_environment_text,
        ),
        (
            relative(mac_runtime_environment_path),
            "let operationLeaseOwner = JSONFileRuntimeOperationLeaseRepository(",
            mac_runtime_environment_text,
        ),
        (
            relative(mac_runtime_environment_path),
            "url: installedPaths.runtimeOperationLease",
            mac_runtime_environment_text,
        ),
        (
            relative(mac_runtime_environment_path),
            "operationLeaseReader: operationLeaseController",
            mac_runtime_environment_text,
        ),
        (
            relative(swift_read_models_path),
            "fromInstallStateRead(_ read: RuntimeInstallStateRead)",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "public let state: RuntimeOperationResourceReadState",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "public static func loaded(_ document: RuntimeInstallStateDocument)",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "public static func unavailable()",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "public static func failed(_ error: String)",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "switch read.state",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "self.document = try container.decodeRequiredNullable(RuntimeInstallStateDocument.self, forKey: .document)",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "self.document = try container.decodeRequiredNullable(RuntimeOperationLeaseDocument.self, forKey: .document)",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "let activeOperation = try container.decodeRequiredNullable(RuntimeOperation.self, forKey: .activeOperation)",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "let lease = try container.decode(RuntimeOperationLeaseState.self, forKey: .lease)",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "loaded install operation state must include document",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "stale operation lease state must include staleReason",
            read_models_text,
        ),
        (
            relative(swift_contract_tests_path),
            "testPlatformOperationStateRequiresExplicitOwnerSubresourceFields",
            swift_contract_tests_text,
        ),
        (
            relative(swift_contract_tests_path),
            "testPlatformOperationStateRejectsInvalidLoadedFailedAndStaleSubresources",
            swift_contract_tests_text,
        ),
        (
            relative(swift_client_contract_path),
            "func loadOperationState() -> PlatformOperationState",
            client_contract_text,
        ),
        (
            relative(api_read_handler_path),
            "client.loadOperationState()",
            api_read_handler_text,
        ),
        (
            relative(http_read_routes_path),
            "case .operationState:\n            return try await RuntimeControlHTTPResponseFactory.json(handler.loadOperationState())",
            http_read_routes_text,
        ),
    ]
    missing = [
        f"{path}:{token}"
        for path, token, text in required
        if token not in text
    ]
    forbidden = [
        (
            relative(swift_read_models_path),
            "fromRuntimeStatusInstallRead",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "install.inProgress",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "var inProgress",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "return .install",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "if let document = read.document",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "if let error = read.error",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "let lease = try container.decodeIfPresent(RuntimeOperationLeaseState.self, forKey: .lease) ?? .unavailable()",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "self.document = try container.decodeIfPresent(RuntimeOperationLeaseDocument.self, forKey: .document)",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "public let issue: RuntimeStatusReadIssue?",
            read_models_text,
        ),
        (
            relative(swift_read_models_path),
            "issue: RuntimeStatusReadIssue?",
            read_models_text,
        ),
        (
            relative(operation_resource_reader_path),
            'RuntimeStatusReadIssue(source: "runtimeInstallState"',
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "RuntimeInstallStateDocumentReader(",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "paths.runtimeInstallState",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "any RuntimeOperationLeaseRepository",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "any RuntimeOperationLeaseMutating",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            operation_resource_reader_text,
        ),
        (
            relative(operation_resource_reader_path),
            "paths.runtimeOperationLease",
            operation_resource_reader_text,
        ),
        (
            relative(read_worker_path),
            "loadOperationState(status:",
            read_worker_text,
        ),
        (
            relative(swift_client_contract_path),
            "loadOperationState(status:",
            client_contract_text,
        ),
        (
            relative(api_read_handler_path),
            "client.loadOperationState(status:",
            api_read_handler_text,
        ),
        (
            relative(read_worker_path),
            "RuntimeInstallStateDocumentReader(",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "paths.runtimeInstallState",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "paths.runtimeOperationLease",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "RuntimeOperationLeaseRepository",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "RuntimeOperationLeaseMutating",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "loadInstallState()",
            read_worker_text,
        ),
        (
            relative(read_worker_path),
            "loadOperationLease()",
            read_worker_text,
        ),
    ]
    present += [
        f"{path}:{token}"
        for path, token, text in forbidden
        if token in text
    ]
    if present or missing:
        return CheckResult(
            "runtime-operation-state-no-status-updated-at",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "runtime-operation-state-no-status-updated-at",
        True,
        "PlatformOperationState contract does not expose legacy RuntimeStatus snapshot freshness "
        "and live operation-state reads do not consume install-state files or RuntimeStatus input",
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
        if path.name == "RuntimeProgressDocumentReader.swift" and not path.exists():
            continue
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
        ROOT / "docs/runtime/runtime-control.openapi.json",
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


def check_runtime_observed_events_do_not_read_status_document_previous_status(
) -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Support"
        / "RuntimeLifecycle+ObservabilitySupport.swift"
    )
    factory_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/Observability/RuntimeEventFactory.swift"
    )
    publisher_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/Observability/RuntimeEventPublisher.swift"
    )
    text = read(path)
    factory_text = read(factory_path)
    publisher_text = read(publisher_path)
    required = [
        "previousStatus: {",
    ]
    forbidden = [
        "statusReporter.loadStatusResult",
        "previousRuntimeStatus",
        "runtimeStatusValue",
        "RuntimeStatusDocumentLoadResult",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    event_forbidden = [
        "statusDocumentEvent",
        "recordStatusDocumentEvent",
        "RuntimeStatusDocument,",
        "statusDocument.status",
        "statusDocument.vmState",
        "statusDocument.failureReasons",
    ]
    present += [
        f"{relative(factory_path)}:{token}"
        for token in event_forbidden
        if token in factory_text
    ]
    present += [
        f"{relative(publisher_path)}:{token}"
        for token in event_forbidden
        if token in publisher_text
    ]
    if missing or present:
        return CheckResult(
            "runtime-observed-events-no-status-document-previous-status",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-observed-events-no-status-document-previous-status",
        True,
        "Observed event previousStatus is not recreated from runtime-status.json snapshots",
    )


def check_runtime_status_document_does_not_own_progress_state() -> CheckResult:
    paths = {
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared/RuntimeStatusDocument.swift"
        ): [
            "public let progress",
            "progress: RuntimeProgressDocument",
            "self.progress",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Domain/Models/RuntimeStatusDocumentBuilder.swift"
        ): [
            "public let progress",
            "progress: RuntimeProgressDocument",
            "progress: input.progress",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Application/UseCases/RuntimeOperationReporting"
            / "BuildRuntimeStatusDocumentUseCase.swift"
        ): [
            "public let progress",
            "progress: RuntimeProgressDocument",
            "progress: input.progress",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence/RuntimeStatusReporter.swift"
        ): [
            "latestBackup: URL?,\n        progress:",
            "latestBackup?.path,\n            progress:",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence/RuntimeStatusWriter.swift"
        ): [
            "message: String,\n        progress:",
            "latestBackup: try latestBackup(),\n            progress:",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Application/UseCases/Observability"
            / "RuntimeObservedStatusPublisher.swift"
        ): [
            "RuntimeProgressDocument?",
            "writeStatus(status, operation, message, progress)",
        ],
    }
    matches: list[str] = []
    for path, tokens in paths.items():
        if path.name == "RuntimeProgressDocumentReader.swift" and not path.exists():
            continue
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token!r}")
    if matches:
        return CheckResult(
            "runtime-status-document-no-progress-state",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-status-document-no-progress-state",
        True,
        "runtime-status.json does not own current progress state",
    )


def check_runtime_status_document_does_not_own_current_health_state(
) -> CheckResult:
    paths = {
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared/RuntimeStatusDocument.swift"
        ): [
            "public let vmState",
            "public let vmErrors",
            "public let failureReasons",
            "public let domainErrors",
            "self.vmState",
            "self.vmErrors",
            "self.failureReasons",
            "self.domainErrors",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Domain/Models/RuntimeStatusDocumentBuilder.swift"
        ): [
            "vmState: input.healthSnapshot",
            "vmErrors: input.healthSnapshot",
            "failureReasons: RuntimeStatusFailureReasonPolicy",
            "domainErrors:",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Application/UseCases/RuntimeOperationReporting"
            / "BuildRuntimeStatusDocumentUseCase.swift"
        ): [
            "vmState:",
            "vmErrors:",
            "failureReasons:",
            "domainErrors:",
        ],
    }
    matches: list[str] = []
    for path, tokens in paths.items():
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token!r}")
    if matches:
        return CheckResult(
            "runtime-status-document-no-current-health-state",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-status-document-no-current-health-state",
        True,
        "runtime-status.json does not own VM health, VM errors, or failure reasons",
    )


def check_runtime_progress_document_failure_does_not_own_current_status_issue(
) -> CheckResult:
    paths = {
        (
            MACOS_RUNTIME
            / "Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift"
        ): [
            "[progressRead.issue]",
            "progressRead.issue].compactMap",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
            / "RuntimeProgressDocumentReader.swift"
        ): [
            'RuntimeStatusReadIssue(source: "runtimeProgress"',
        ],
    }
    matches: list[str] = []
    for path, tokens in paths.items():
        if path.name == "RuntimeProgressDocumentReader.swift" and not path.exists():
            continue
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token!r}")
    if matches:
        return CheckResult(
            "runtime-progress-document-failure-no-current-status-issue",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-progress-document-failure-no-current-status-issue",
        True,
        "runtime-progress.json read failures do not own current status issues",
    )


def check_runtime_progress_artifact_sink_is_write_only(
) -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeProgressDocument.swift",
        MACOS_RUNTIME / "Sources/Application/Ports/RuntimeProgressArtifactSink.swift",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence"
            / "JSONFileRuntimeProgressArtifactSink.swift"
        ),
    ]
    forbidden = [
        "RuntimeProgressDocumentLoadResult",
        "func loadResult()",
        "return .loaded",
        "return .missing",
        "return .failed",
        "let runtimeProgress: String",
        "runtimeProgress: String = RuntimeControlClientConstants.Paths.runtimeProgress",
        "self.runtimeProgress",
    ]
    matches = [
        f"{relative(path)}:{token}"
        for path in paths
        for token in forbidden
        if token in read(path)
    ]
    docs_runtime_macos = ROOT / "docs/runtime/macos"
    doc_forbidden = {
        docs_runtime_macos / "observability.md": [
            "Runtime Control API progress input",
            "workflow progress, Host service liveness",
            "| `status/runtime-progress.json` | HostCLI workflow | Helper UI, Runtime Control API |",
            "Host workflow progress display/support artifact",
            "write-only display artifact",
        ],
        docs_runtime_macos / "update.md": [
            "| `runtime-progress.json` | host Updater/Supervisor | Helper UI |",
            "`runtime-progress.json` display artifact",
            "support/export diagnostics",
            "support/export workflow progress artifact",
            "support/export progress artifact",
        ],
        docs_runtime_macos / "runtime.md": [
            "Workflow progress 표시는 `runtime-progress.json`에서 읽지만",
            "support/export workflow progress artifact",
        ],
        docs_runtime_macos / "packaging.md": [
            "Helper/API-visible progress artifact",
            "Helper/API용 workflow progress artifact",
            "support/export workflow progress artifact",
            "support/export progress artifact",
        ],
        docs_runtime_macos / "state-machine-traceability.md": [
            "support/export workflow progress artifact",
        ],
        ROOT / "docs/runtime/runtime-control.openapi.json": [
            "lease owner may persist through a transitional local artifact",
        ],
    }
    for path, tokens in doc_forbidden.items():
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token}")
    artifact_sink_text = read(
        MACOS_RUNTIME / "Sources/Application/Ports/RuntimeProgressArtifactSink.swift"
    )
    if "func save(_ document: RuntimeProgressDocument) throws" not in artifact_sink_text:
        matches.append("RuntimeProgressArtifactSink.save")
    if matches:
        return CheckResult(
            "runtime-progress-artifact-sink-write-only",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-progress-artifact-sink-write-only",
        True,
        "runtime-progress.json artifact sink is a write-only diagnostics/export artifact sink",
    )


def check_runtime_status_artifact_sink_is_write_only(
) -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeStatusDocument.swift",
        MACOS_RUNTIME / "Sources/Application/Ports/RuntimeStatusArtifactSink.swift",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence"
            / "JSONFileRuntimeStatusArtifactSink.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence"
            / "RuntimeStatusReporter.swift"
        ),
    ]
    forbidden = [
        "RuntimeStatusDocumentLoadResult",
        "func loadResult()",
        "loadStatusResult",
        "return .loaded",
        "return .missing",
        "return .failed",
        "let runtimeStatus: String",
        "runtimeStatus: String = RuntimeControlClientConstants.Paths.runtimeStatus",
        "self.runtimeStatus",
    ]
    matches = [
        f"{relative(path)}:{token}"
        for path in paths
        for token in forbidden
        if token in read(path)
    ]
    docs_runtime_macos = ROOT / "docs/runtime/macos"
    doc_forbidden = {
        docs_runtime_macos / "observability.md": [
            "- 최신 상태는 `runtime-status.json`에 반영합니다.",
        ],
        docs_runtime_macos / "update.md": [
            "| `runtime-status.json` | host Updater/Supervisor | Helper UI |",
        ],
        ROOT / "site-docs/dev/backup-restore-contracts.md": [
            "UI continuity용 optional state",
            "UI continuity용 optional event history",
            "UI continuity용 optional projection snapshot",
            "optional continuity artifact",
            "restore는 대체 상태를 만들지 않고",
        ],
        ROOT / "site-docs/dev/runtime-contracts.md": [
            "`runtime-status.json` 파일이 아직 생성되지 않음",
            "파일 권한 문제로 status를 읽지 못함",
        ],
    }
    for path, tokens in doc_forbidden.items():
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token}")
    artifact_sink_text = read(
        MACOS_RUNTIME / "Sources/Application/Ports/RuntimeStatusArtifactSink.swift"
    )
    if "func save(_ document: RuntimeStatusDocument) throws" not in artifact_sink_text:
        matches.append("RuntimeStatusArtifactSink.save")
    if matches:
        return CheckResult(
            "runtime-status-artifact-sink-write-only",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-status-artifact-sink-write-only",
        True,
        "runtime-status.json artifact sink is a write-only diagnostics/export artifact sink",
    )


def check_runtime_diagnostics_artifact_file_names_are_separate() -> CheckResult:
    runtime_file_names_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeFileNames.swift"
    )
    diagnostics_file_names_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeDiagnosticsArtifactFileNames.swift"
    )
    product_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/FileSystem/InstalledRuntimePaths.swift"
        ),
        MACOS_RUNTIME / "Sources/Bootstrap/Composition/Constants.swift",
        (
            MACOS_RUNTIME
            / "Sources/Contracts/RuntimeControl/RuntimeLogExportSourceContracts.swift"
        ),
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeDataBackupDocuments.swift",
    ]
    guest_contracts_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/contracts.py"
    )
    guest_product_paths = [
        GUEST_TOOLS / "pyproject.toml",
        GUEST_TOOLS / "src/tirosh_guest_tools/infrastructure/system_install.py",
        GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_observation.py",
        GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_boot_smoke.py",
        (
            GUEST_TOOLS
            / "src/tirosh_guest_tools/adapters/outbound/observability/collectors.py"
        ),
        MACOS_RUNTIME / "Support/Guest/bin/tirosh-runtime-observation",
        MACOS_RUNTIME / "Support/Guest/bin/tirosh-write-runtime-observation",
        MACOS_RUNTIME / "Support/Guest/systemd/tirosh-runtime-observation.service",
        (
            MACOS_RUNTIME
            / "Support/Guest/systemd/tirosh-vitalserver-container-logs.service"
        ),
        (
            MACOS_RUNTIME
            / "Support/Guest/systemd/tirosh-vitalserver-sync-host-time.service"
        ),
    ]
    diagnostics_artifacts = [
        "runtimeStatus",
        "runtimeProgress",
        "runtimeEvents",
        "runtimeObservabilityDB",
        "runtimeObservation",
        "bootstrapResult",
    ]

    diagnostics_file_names_text = read(diagnostics_file_names_path)
    product_text = "\n".join(read(path) for path in product_paths)
    guest_contracts_text = read(guest_contracts_path)
    guest_product_text = "\n".join(read(path) for path in guest_product_paths)

    forbidden = []
    if runtime_file_names_path.exists():
        forbidden.append(
            f"{relative(runtime_file_names_path)}:generic RuntimeFileNames must be removed"
        )
    guest_forbidden = [
        "RuntimeFileName.RUNTIME_STATE",
        "RuntimeFileName.BOOTSTRAP_RESULT",
        "RuntimeCommand.RUNTIME_STATE",
        "RuntimeCommand.WRITE_RUNTIME_STATE",
        "RuntimeService.RUNTIME_STATE",
        "RuntimeStateAction",
        "tirosh-runtime-state",
        "tirosh-write-runtime-state",
        "write_current_state",
    ]
    forbidden += [
        f"guest-tools:{token}"
        for token in guest_forbidden
        if token in guest_contracts_text or token in guest_product_text
    ]
    missing = [
        name
        for name in diagnostics_artifacts
        if f"public static let {name}" not in diagnostics_file_names_text
    ]
    guest_missing = [
        token
        for token in [
            "class RuntimeDiagnosticsArtifactFileName",
            'RUNTIME_OBSERVATION = "runtime-observation.json"',
            'BOOTSTRAP_RESULT = "bootstrap-result.json"',
            "RuntimeDiagnosticsArtifactFileName.RUNTIME_OBSERVATION",
            "RuntimeDiagnosticsArtifactFileName.BOOTSTRAP_RESULT",
            "RuntimeCommand.RUNTIME_OBSERVATION",
            "RuntimeCommand.WRITE_RUNTIME_OBSERVATION",
            "RuntimeService.RUNTIME_OBSERVATION",
            "RuntimeObservationAction",
            "tirosh-runtime-observation",
            "tirosh-write-runtime-observation",
            "write_runtime_observation_outputs",
        ]
        if token not in guest_contracts_text + guest_product_text
    ]
    missing_product_uses = [
        name
        for name in diagnostics_artifacts
        if f"RuntimeDiagnosticsArtifactFileNames.{name}" not in product_text
    ]

    if forbidden or missing or missing_product_uses or guest_missing:
        return CheckResult(
            "runtime-diagnostics-artifact-file-names-separate",
            False,
            "forbidden_runtime_file_names="
            f"{forbidden} missing_diagnostics_names={missing} "
            f"missing_product_uses={missing_product_uses} "
            f"guest_missing={guest_missing}",
        )
    return CheckResult(
        "runtime-diagnostics-artifact-file-names-separate",
        True,
        "diagnostics/export artifact names are separate from current owner contract names",
    )


def check_runtime_current_owner_file_names_are_separate() -> CheckResult:
    runtime_file_names_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeFileNames.swift"
    )
    bootstrap_evidence_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeBootstrapEvidenceFileNames.swift"
    )
    host_owner_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeHostOwnerFileNames.swift"
    )
    guest_address_read_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeGuestAddressReadResult.swift"
    )
    runtime_control_constants_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Environment"
        / "RuntimeControlClientConstants.swift"
    )
    bootstrap_constants_path = MACOS_RUNTIME / "Sources/Bootstrap/Composition/Constants.swift"
    product_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/FileSystem/InstalledRuntimePaths.swift"
        ),
        bootstrap_constants_path,
        (
            MACOS_RUNTIME
            / "Sources/Contracts/RuntimeControl/RuntimeLogExportSourceContracts.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs"
            / "RuntimeLogCollectionSources.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs"
            / "RuntimeLogExportSources.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
            / "RuntimeLogSourceReadStrategy.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs"
            / "MacRuntimeControlLogExporter.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
            / "RuntimeFileReaders.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
            / "RuntimeShellCommandFactory.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
            / "RuntimeUninstallCommandFactory.swift"
        ),
    ]
    bootstrap_evidence_text = read(bootstrap_evidence_path)
    host_owner_text = read(host_owner_path)
    guest_address_read_text = read(guest_address_read_path)
    runtime_control_constants_text = read(runtime_control_constants_path)
    bootstrap_constants_text = read(bootstrap_constants_path)
    product_text = "\n".join(read(path) for path in product_paths)
    guest_contracts_path = GUEST_TOOLS / "src/tirosh_guest_tools/contracts.py"
    guest_runtime_state_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_observation.py"
    )
    guest_contracts_text = read(guest_contracts_path)
    guest_runtime_state_text = read(guest_runtime_state_path)
    forbidden = []
    if runtime_file_names_path.exists():
        forbidden.append(f"{relative(runtime_file_names_path)}:generic RuntimeFileNames must be removed")
    forbidden += [
        token
        for token in [
            "RuntimeFileNames.vmIP",
            "RuntimeFileNames.vmLifecycle",
        ]
        if token in product_text
    ]
    if "RuntimeFileName.VM_IP" in guest_contracts_text + guest_runtime_state_text:
        forbidden.append("guest-tools:RuntimeFileName.VM_IP")
    if 'case vmIPFile = "vm-ip"' in guest_address_read_text:
        forbidden.append(f"{relative(guest_address_read_path)}:case vmIPFile")
    forbidden += [
        f"{relative(runtime_control_constants_path)}:{token}"
        for token in [
            "static let vmIPFile",
            "static let runtimeObservation",
            "static let runtimeStatus",
            "static let runtimeProgress",
            "static let runtimeEvents",
            "static let runtimeObservabilityDB",
            "static let vmLifecycle",
            "static let runtimeOperationLease",
            "static let bootstrapResult",
        ]
        if token in runtime_control_constants_text
    ]
    forbidden += [
        f"{relative(bootstrap_constants_path)}:{token}"
        for token in [
            "public static let runtimeStatus = RuntimeDiagnosticsArtifactFileNames.runtimeStatus",
            "public static let vmIPFile = RuntimeBootstrapEvidenceFileNames.vmIP",
            "public static let runtimeObservationFile = RuntimeDiagnosticsArtifactFileNames.runtimeObservation",
            "public static let bootstrapResultFile = RuntimeDiagnosticsArtifactFileNames.bootstrapResult",
        ]
        if token in bootstrap_constants_text
    ]
    required = [
        (
            relative(bootstrap_evidence_path),
            'public static let vmIP = "vm-ip"',
            bootstrap_evidence_text,
        ),
        (
            relative(host_owner_path),
            'public static let vmLifecycle = "vm-lifecycle.json"',
            host_owner_text,
        ),
        (
            relative(host_owner_path),
            'public static let runtimeEndpoint = "runtime-endpoint.json"',
            host_owner_text,
        ),
        (
            relative(host_owner_path),
            'public static let operationLease = "runtime-operation-lease.json"',
            host_owner_text,
        ),
        (
            "production",
            "RuntimeBootstrapEvidenceFileNames.vmIP",
            product_text,
        ),
        (
            "production",
            "RuntimeHostOwnerFileNames.vmLifecycle",
            product_text,
        ),
        (
            "production",
            "RuntimeHostOwnerFileNames.runtimeEndpoint",
            product_text,
        ),
        (
            "production",
            "RuntimeHostOwnerFileNames.operationLease",
            product_text,
        ),
        (
            relative(guest_contracts_path),
            "class RuntimeBootstrapEvidenceFileName",
            guest_contracts_text,
        ),
        (
            relative(guest_contracts_path),
            'VM_IP = "vm-ip"',
            guest_contracts_text,
        ),
        (
            relative(guest_runtime_state_path),
            "RuntimeBootstrapEvidenceFileName.VM_IP",
            guest_runtime_state_text,
        ),
    ]
    missing = [
        f"{path}:{token}"
        for path, token, text in required
        if token not in text
    ]
    if forbidden or missing:
        return CheckResult(
            "runtime-current-owner-file-names-separate",
            False,
            f"forbidden={forbidden} missing={missing}",
        )
    return CheckResult(
        "runtime-current-owner-file-names-separate",
        True,
        "bootstrap address evidence and Host VM lifecycle names are not generic runtime file names",
    )


def check_runtime_log_artifact_file_names_are_separate() -> CheckResult:
    runtime_file_names_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeFileNames.swift"
    )
    log_artifact_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeLogArtifactFileNames.swift"
    )
    product_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/FileSystem/InstalledRuntimePaths.swift"
        ),
        MACOS_RUNTIME / "Sources/Bootstrap/Composition/Constants.swift",
        (
            MACOS_RUNTIME
            / "Sources/Contracts/RuntimeControl/RuntimeLogCollectionSourceContracts.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Contracts/RuntimeControl/RuntimeLogExportSourceContracts.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs"
            / "RuntimeLogCollectionSources.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs"
            / "RuntimeLogExportSources.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
            / "RuntimeLogSourceReadStrategy.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs"
            / "MacRuntimeControlLogExporter.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
            / "RuntimeFileReaders.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
            / "RuntimeShellCommandFactory.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
            / "RuntimeUninstallCommandFactory.swift"
        ),
    ]
    log_artifacts = [
        "bootstrapLog",
        "datastoreRepairLog",
        "redisBackupLog",
        "redisRestoreLog",
        "updateActivationLog",
        "updateShutdownLog",
        "containerLogs",
        "managerCommandLog",
        "managerHelperMessageLog",
        "runtimeUninstallLog",
    ]
    log_artifact_text = read(log_artifact_path)
    product_text = "\n".join(read(path) for path in product_paths)
    forbidden = []
    if runtime_file_names_path.exists():
        forbidden.append(f"{relative(runtime_file_names_path)}:generic RuntimeFileNames must be removed")
    forbidden += [
        name
        for name in log_artifacts
        if f"RuntimeFileNames.{name}" in product_text
    ]
    log_path_forbidden = [
        "RuntimeControlClientConstants.Paths.runtimeLogSources",
        "RuntimeControlClientConstants.Paths.bootstrapLogSource",
        "RuntimeControlClientConstants.Paths.containerLogSource",
        "RuntimeControlClientConstants.Paths.updateActivationLogSource",
        "RuntimeControlClientConstants.Paths.updateShutdownLogSource",
        "RuntimeControlClientConstants.Paths.datastoreRepairLogSource",
        "RuntimeControlClientConstants.Paths.redisBackupLogSource",
        "RuntimeControlClientConstants.Paths.guestObservabilitySource",
        "RuntimeControlClientConstants.Paths.commandLogFile",
        "RuntimeControlClientConstants.Paths.helperMessageLogFile",
        "RuntimeControlClientConstants.Paths.guestRunDirectory",
        "RuntimeControlClientConstants.Paths.runtimeLogs",
        "RuntimeControlClientConstants.Paths.guestLogs",
        "RuntimeControlClientConstants.Paths.productLogs",
        "RuntimeControlClientConstants.Paths.installLog",
        "RuntimeControlClientConstants.Paths.uninstallLog",
    ]
    forbidden += [
        token
        for token in log_path_forbidden
        if token in product_text
    ]
    installed_path_required = [
        "InstalledRuntimePaths.defaultInstalled",
        "installed.logsDirectory",
        "installed.bootstrapLog",
        "installed.containerLogs",
        "installed.updateActivationLog",
        "installed.updateShutdownLog",
        "installed.datastoreRepairLog",
        "installed.redisBackupLog",
        "installed.managerCommandLog",
        "installed.productLogsDirectory",
        "InstalledRuntimePaths.defaultInstalled.runtimeUninstallLog",
    ]
    missing = [
        name
        for name in log_artifacts
        if f"public static let {name}" not in log_artifact_text
        or f"RuntimeLogArtifactFileNames.{name}" not in product_text
    ]
    missing += [
        token
        for token in installed_path_required
        if token not in product_text
    ]
    if forbidden or missing:
        return CheckResult(
            "runtime-log-artifact-file-names-separate",
            False,
            f"forbidden={forbidden} missing={missing}",
        )
    return CheckResult(
        "runtime-log-artifact-file-names-separate",
        True,
        "runtime log artifact names are separate from generic runtime file names",
    )


def check_runtime_generic_file_names_are_removed() -> CheckResult:
    runtime_file_names_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeFileNames.swift"
    )
    package_artifact_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimePackageArtifactFileNames.swift"
    )
    host_contract_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeHostContractFileNames.swift"
    )
    workflow_artifact_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeWorkflowArtifactFileNames.swift"
    )
    package_artifact_text = read(package_artifact_path)
    host_contract_text = read(host_contract_path)
    workflow_artifact_text = read(workflow_artifact_path)

    required = [
        (relative(package_artifact_path), 'public static let rootfsBase = "rootfs-base.raw.gz"', package_artifact_text),
        (relative(package_artifact_path), 'public static let runtimeVersion = "runtime-version.json"', package_artifact_text),
        (relative(package_artifact_path), 'public static let backupManifest = "backup-manifest.json"', package_artifact_text),
        (relative(package_artifact_path), 'public static let updateBundleManifest = "manifest.json"', package_artifact_text),
        (relative(host_contract_path), 'public static let appliedVMConfig = "applied-vm-config.json"', host_contract_text),
        (relative(host_contract_path), 'public static let hostTime = "host-time.json"', host_contract_text),
        (
            relative(workflow_artifact_path),
            'public static let runtimeInstallState = "tirosh-vitalserver-install-state.json"',
            workflow_artifact_text,
        ),
        (
            relative(workflow_artifact_path),
            'public static let runtimeUninstallState = "tirosh-vitalserver-uninstall-state.json"',
            workflow_artifact_text,
        ),
    ]
    missing = [
        f"{path}:{token}"
        for path, token, text in required
        if token not in text
    ]
    forbidden = []
    if runtime_file_names_path.exists():
        forbidden.append(f"{relative(runtime_file_names_path)}:generic RuntimeFileNames file must be removed")
    forbidden += find_tokens(
        [MACOS_RUNTIME / "Sources"],
        ["RuntimeFileNames."],
    )
    if missing or forbidden:
        return CheckResult(
            "runtime-generic-file-names-removed",
            False,
            f"missing={missing} forbidden={forbidden[:10]}",
        )
    return CheckResult(
        "runtime-generic-file-names-removed",
        True,
        "generic RuntimeFileNames is removed in favor of role-specific file-name contracts",
    )


def check_runtime_settings_paths_use_installed_paths_defaults() -> CheckResult:
    settings_reader_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Settings/RuntimeSettingsReader.swift"
    )
    text = read(settings_reader_path)
    required = [
        "InstalledRuntimePaths.defaultInstalled.vmConfig.path",
        "InstalledRuntimePaths.defaultInstalled.appliedVMConfig.path",
        "InstalledRuntimePaths.defaultInstalled.vmDisk.path",
        "InstalledRuntimePaths.defaultInstalled.guestRuntimeSettings.path",
        "InstalledRuntimePaths.defaultInstalled.runtimeControlSettings.path",
        "InstalledRuntimePaths.defaultInstalled.proxyLaunchDaemon.path",
    ]
    forbidden = [
        "RuntimeControlClientConstants.Paths.vmConfig",
        "RuntimeControlClientConstants.Paths.appliedVMConfig",
        "RuntimeControlClientConstants.Paths.vmDisk",
        "RuntimeControlClientConstants.Paths.guestRuntimeSettings",
        "RuntimeControlClientConstants.Paths.runtimeControlSettings",
        "RuntimeControlClientConstants.Paths.proxyLaunchDaemon",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if missing or present:
        return CheckResult(
            "runtime-settings-paths-installed-defaults",
            False,
            f"missing={missing} forbidden_present={present} path={relative(settings_reader_path)}",
        )
    return CheckResult(
        "runtime-settings-paths-installed-defaults",
        True,
        "Runtime settings reader default config paths come from InstalledRuntimePaths",
    )


def check_runtime_workflow_state_artifact_writers_are_named_as_artifacts() -> CheckResult:
    install_store_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Persistence/RuntimeInstallWorkflowStateArtifactStore.swift"
    )
    uninstall_store_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Persistence/RuntimeUninstallWorkflowStateArtifactStore.swift"
    )
    install_test_path = (
        MACOS_RUNTIME
        / "Tests/CLIHostTests/RuntimeInstallWorkflowStateArtifactStoreTests.swift"
    )
    uninstall_test_path = (
        MACOS_RUNTIME
        / "Tests/CLIHostTests/RuntimeUninstallWorkflowStateArtifactStoreTests.swift"
    )
    runtime_control_constants_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Environment"
        / "RuntimeControlClientConstants.swift"
    )
    required = [
        (
            relative(install_store_path),
            "public struct RuntimeInstallWorkflowStateArtifactStore",
            read(install_store_path),
        ),
        (
            relative(uninstall_store_path),
            "public struct RuntimeUninstallWorkflowStateArtifactStore",
            read(uninstall_store_path),
        ),
        (
            relative(install_test_path),
            "final class RuntimeInstallWorkflowStateArtifactStoreTests",
            read(install_test_path),
        ),
        (
            relative(uninstall_test_path),
            "final class RuntimeUninstallWorkflowStateArtifactStoreTests",
            read(uninstall_test_path),
        ),
    ]
    missing = [
        f"{path}:{token}"
        for path, token, text in required
        if token not in text
    ]
    forbidden = find_tokens(
        [
            MACOS_RUNTIME / "Sources",
            MACOS_RUNTIME / "Tests",
            ROOT / "docs",
            ROOT / "site-docs",
        ],
        [
            "RuntimeInstallStateStore",
            "RuntimeUninstallStateStore",
            "runtimeStateDocumentEncoder",
            "Host-owned lifecycle document at `/private/tmp/tirosh-vitalserver-uninstall-state.json`",
        ],
    )
    constants_text = read(runtime_control_constants_path)
    for token in [
        "runtimeInstallState = installed.runtimeInstallState.path",
        "runtimeUninstallState = installed.runtimeUninstallState.path",
    ]:
        if token in constants_text:
            forbidden.append(
                f"{relative(runtime_control_constants_path)}:{token}: workflow artifacts must not be exposed through product RuntimeControlClient path constants"
            )
    if missing or forbidden:
        return CheckResult(
            "runtime-workflow-state-artifact-writers-named-as-artifacts",
            False,
            f"missing={missing} forbidden={forbidden[:10]}",
        )
    return CheckResult(
        "runtime-workflow-state-artifact-writers-named-as-artifacts",
        True,
        "install/uninstall workflow state files are named as workflow artifacts, not current state stores",
    )


def check_runtime_status_document_does_not_own_active_operation_state(
) -> CheckResult:
    paths = {
        (
            MACOS_RUNTIME
            / "Sources/Contracts/Shared/RuntimeStatusDocument.swift"
        ): [
            "public let operation",
            "public let message",
            "public let updatedAt",
            "self.operation",
            "self.message",
            "self.updatedAt",
            "operation: RuntimeOperation",
            "operation: String",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Domain/Models/RuntimeStatusDocumentBuilder.swift"
        ): [
            "public let operation",
            "public let message",
            "public let updatedAt",
            "operation: input.operation",
            "message: input.message",
            "updatedAt: input.updatedAt",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Application/UseCases/RuntimeOperationReporting"
            / "BuildRuntimeStatusDocumentUseCase.swift"
        ): [
            "RuntimeStatusDocumentInput(\n            product: input.product,\n            status: input.status,\n            operation:",
            "RuntimeStatusDocumentBuildInput: Equatable {\n    public let product: String\n    public let status: RuntimeStatusLevel\n    public let operation",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence/RuntimeStatusReporter.swift"
        ): [
            "public func writeStatus(\n        _ status: RuntimeStatusLevel,\n        operation:",
            "message: String,\n        runtimeVersion:",
            "updatedAt: String,\n        runtimeVersion:",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence/RuntimeStatusWriter.swift"
        ): [
            "public func writeStatus(\n        _ status: RuntimeStatusLevel,\n        operation:",
            "message: String\n    ) throws -> RuntimeHealthSnapshot",
            "timestamp(),\n            runtimeVersion:",
        ],
        (
            MACOS_RUNTIME
            / "Sources/Application/UseCases/Observability"
            / "RuntimeObservedStatusPublisher.swift"
        ): [
            "public let writeStatus: (\n        RuntimeStatusLevel,\n        RuntimeOperation",
            "writeStatus(status, operation, message)",
        ],
    }
    matches: list[str] = []
    for path, tokens in paths.items():
        text = read(path)
        for token in tokens:
            if token in text:
                matches.append(f"{relative(path)}:{token!r}")
    if matches:
        return CheckResult(
            "runtime-status-document-no-active-operation-state",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-status-document-no-active-operation-state",
        True,
        "runtime-status.json does not own active operation, message, or timestamps",
    )


def check_runtime_status_document_failure_reasons_are_not_current_health(
) -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeFailureReason.swift",
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Copy"
            / "AppConstants+StatusText.swift"
        ),
    ]
    forbidden = [
        "case runtimeStatusDocumentMissing",
        "case runtimeStatusDocumentStale",
        "case runtimeStatusDocumentInvalid",
        "runtimeStatusDocumentMissing",
        "runtimeStatusDocumentStale",
        "runtimeStatusDocumentInvalid",
        "runtime-status-document-missing",
        "runtime-status-document-stale",
        "runtime-status-document-invalid",
    ]
    matches = find_tokens(paths, forbidden)
    if matches:
        return CheckResult(
            "runtime-status-document-failure-reasons-not-current-health",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-status-document-failure-reasons-not-current-health",
        True,
        "runtime-status.json diagnostics are not modeled as current health failure reasons",
    )


def check_runtime_data_restore_does_not_restore_runtime_status_projection(
) -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Persistence/RuntimeDataBackupStore.swift"
    )
    contracts_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeDataBackupDocuments.swift"
    )
    tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests/RuntimeDataBackupStoreTests.swift"
    )
    backup_docs_path = ROOT / "docs/runtime/macos/runtime-data-backup.md"
    troubleshooting_path = (
        ROOT / "docs/troubleshooting/079_runtime-data-restore-silent-failure.md"
    )
    text = read(path)
    contracts_text = read(contracts_path)
    tests_text = read(tests_path)
    backup_docs_text = read(backup_docs_path)
    troubleshooting_text = read(troubleshooting_path)
    forbidden = [
        "restoreOptionalFile(.runtimeStatusDocument",
        "restoreRequiredFile(.runtimeStatusDocument",
        "destination: paths.runtimeStatus",
        "guard let source = try? artifactURL",
        "guard let data = try? fileStore.readData(source)",
    ]
    present = [token for token in forbidden if token in text]
    present += [
        f"{relative(contracts_path)}:{token}"
        for token in [
            "requiredForUIContinuity",
            "optionalForUIContinuity",
            "optionalForSupportContinuity",
        ]
        if token in contracts_text
    ]
    if "optionalForDiagnosticsContinuity" not in contracts_text:
        present.append(f"{relative(contracts_path)}:missing optionalForDiagnosticsContinuity")
    if "restore must not write it back to current `runtime-status.json`" not in backup_docs_text:
        present.append(f"{relative(backup_docs_path)}:missing runtime-status restore prohibition")
    required = [
        ("RuntimeDataBackupStore.optionalArtifactInvalid", "case optionalArtifactInvalid", text),
        ("RuntimeDataBackupStore.optionalVerifiedArtifactThrows", "throws -> URL?", text),
        (
            "RuntimeDataBackupStore.restoreOptionalFileThrows",
            "try optionalVerifiedArtifact(id, artifacts: artifacts, backup: backup)",
            text,
        ),
        (
            "RuntimeDataBackupStoreTests.optionalDiagnosticsArtifactFailure",
            "testRestoreBackupFailsWhenArchivedOptionalDiagnosticsArtifactIsMissing",
            tests_text,
        ),
        (
            "TS-079.optionalArtifactValidationFailureDistinct",
            "Optional artifact absence and optional artifact validation failure must stay distinct.",
            troubleshooting_text,
        ),
    ]
    for label, token, source_text in required:
        if token not in source_text:
            present.append(f"missing {label}")
    for token in [
        "| `runtime-status-document` | Host | Host runtime status document *(optional: 없으면 skip)* |",
        "| `runtime-events-document` | Host | Host runtime event document *(optional: 없으면 skip)* |",
        "| `runtime-observability-database` | Host | `runtime-observability.sqlite` snapshot *(optional: 없으면 skip)* |",
    ]:
        if token in backup_docs_text:
            present.append(f"{relative(backup_docs_path)}:{token}")
    if present:
        return CheckResult(
            "runtime-data-restore-no-runtime-status-projection-restore",
            False,
            f"forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "runtime-data-restore-no-runtime-status-projection-restore",
        True,
        "runtime data restore does not restore runtime-status.json as current state",
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
        MACOS_RUNTIME / "Sources/Contracts/Shared/GuestRuntimeObservationDocument.swift": [
            "containerServices",
            "RuntimeContainerServiceObservation",
            "vitalDBObservation",
            "VitalDBObservationDocument",
        ],
        GUEST_TOOLS / "src/tirosh_guest_tools/domain/runtime_observation.py": [
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
            "runtime-observation.json no longer carries container service or "
            "VitalDB observation state"
        ),
    )


def check_runtime_state_document_has_no_capabilities() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Contracts/Shared/GuestRuntimeObservationDocument.swift",
        GUEST_TOOLS / "src/tirosh_guest_tools/domain/runtime_observation.py",
        GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_boot_smoke.py",
        GUEST_TOOLS / "tests/test_runtime_boot_smoke.py",
    ]
    forbidden = [
        "GuestRuntimeCapabilities",
        "RuntimeCapabilities",
        '"capabilities": self.capabilities.as_json()',
        "runtime observation capabilities",
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
        "GUEST_CONTROL_API_BASE_URL}/runtime/capabilities",
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
        "runtime-observation.json no longer carries capability state; "
        "boot smoke checks Guest Control /runtime/capabilities",
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
        "public enum RuntimeGuestRuntimeObservationReadIssue",
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
        "Host health no longer keeps runtime-observation.json guestHTTP/vmIP "
        "promotion or runtime-state freshness observation paths",
    )


def check_runtime_guest_file_gateway_is_maintenance_only() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Application/Ports/RuntimeGuestDocumentReaders.swift",
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeDiagnosticsArtifactFileNames.swift",
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeWorkflowArtifactFileNames.swift",
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeBootstrapEvidenceFileNames.swift",
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeLogArtifactFileNames.swift",
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
        "RuntimeGuestBootstrapResultReader",
        "loadBootstrapResultDocument",
        "JSONFileRuntimeGuestDocumentReader",
    ]
    present = [token for token in forbidden if token in text]
    if present:
        return CheckResult(
            "runtime-guest-file-gateway-maintenance-only",
            False,
            f"forbidden_present={present}",
        )
    return CheckResult(
        "runtime-guest-file-gateway-maintenance-only",
        True,
        "runtime document readers do not expose Guest file-backed state gateways",
    )


def check_legacy_guest_request_result_file_names_are_removed() -> CheckResult:
    paths = [
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeDiagnosticsArtifactFileNames.swift",
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeWorkflowArtifactFileNames.swift",
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeBootstrapEvidenceFileNames.swift",
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeLogArtifactFileNames.swift",
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


def check_redis_backup_file_bridge_is_absent_from_runtime_observation_writer() -> CheckResult:
    runtime_state_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_observation.py"
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
            "redis-backup-file-bridge-runtime-observation-writer",
            False,
            f"forbidden_present={present}",
        )
    return CheckResult(
        "redis-backup-file-bridge-runtime-observation-writer",
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
            '["runtime", "maintenance", "redis-backup"]',
            '["runtime", "maintenance", "redis-restore"]',
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
            '["runtime", "maintenance", "update-activation"]',
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
            'path: "/runtime/maintenance/update-activation"',
            "RuntimeGuestControlUpdateActivationRequest",
        ],
        usecase_path: [
            "activateUpdate(",
            "expectedService: \"update-activation\"",
            "expectedCommand: .updateActivation",
        ],
        guest_api_path: [
            '["runtime", "maintenance", "update-activation"]',
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
            'path: "/runtime/maintenance/update-shutdown"',
            'path: "/runtime/maintenance/guest-poweroff"',
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
            '["runtime", "maintenance", "update-shutdown"]',
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
            'path: "/runtime/maintenance/redis-backup"',
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
            'path: "/runtime/maintenance/redis-restore"',
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
            'path: "/runtime/maintenance/datastore/repair"',
        ],
        relative(usecase_path): [
            "repairDatastore(",
            "expectedService: \"datastore-repair\"",
            "expectedCommand: .repairDatastore",
        ],
        relative(guest_api_path): [
            '["runtime", "maintenance", "datastore", "repair"]',
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
        ROOT / "docs/runtime/runtime-control.openapi.json",
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
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
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
    pwa_hooks_path = PWA / "src/console/hooks.ts"
    pwa_lab_page_path = PWA / "src/pages/lab/LabPage.tsx"
    pwa_pages_test_path = PWA / "src/pages/pages.test.tsx"
    openapi_document = json.loads(read(openapi_path))
    capability_schema = (
        openapi_document.get("components", {})
        .get("schemas", {})
        .get("RuntimeCapabilities", {})
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
    if capability_required != {"schemaVersion", "capabilities"}:
        capability_contract_issues.append(
            "RuntimeCapabilities must require schemaVersion and capabilities"
        )
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
        relative(pwa_hooks_path): read(pwa_hooks_path),
        relative(pwa_lab_page_path): read(pwa_lab_page_path),
        relative(pwa_pages_test_path): read(pwa_pages_test_path),
    }
    required = {
        relative(endpoint_path): [
            'path: "/runtime/lab/scenarios"',
            'path: "/runtime/lab/sessions"',
            'path: "/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start"',
            'path: "/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/stop"',
            'path: "/runtime/lab/vital-files/replay"',
            'path: "/runtime/stack"',
            'path: "/runtime/services/{service}/start"',
            'path: "/runtime/services/{service}/stop"',
            'path: "/runtime/services/{service}/restart"',
            'path: "/runtime/vitaldb/recorders"',
            'path: "/runtime/vitaldb/beds"',
            'path: "/runtime/vitaldb/relationships"',
        ],
        relative(read_handler_path): [
            "try await client.loadLabScenarios()",
            "try await client.loadLabSessions()",
            "try await client.startLabRecorder(",
            "try await client.stopLabRecorder(",
            "try await client.replayLabVitalFile(request)",
            "try await client.guestStackStatus()",
            "try await client.startGuestService(request)",
            "try await client.restartGuestService(request)",
            "client.loadVitalDBRecorders()",
            "client.loadVitalDBRelationships()",
        ],
        relative(openapi_path): [
            '"RuntimeCapabilities"',
            '"/runtime/lab/scenarios"',
            '"/runtime/lab/sessions"',
            '"/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/start"',
            '"/runtime/lab/sessions/{sessionId}/recorders/{recorderId}/stop"',
            '"/runtime/lab/vital-files/replay"',
            '"/runtime/services"',
            '"/runtime/stack"',
            '"/runtime/services/{service}/start"',
            '"/runtime/services/{service}/stop"',
            '"/runtime/services/{service}/restart"',
            '"/runtime/vitaldb/recorders"',
            '"/runtime/vitaldb/beds"',
            '"/runtime/vitaldb/relationships"',
            (
                "Guest/Postgres-owned read model for bed-to-VRecorder assignments "
                "and relationship anomalies"
            ),
        ],
        relative(pwa_generated_path): [
            "capabilities: string[];",
            (
                "Guest/Postgres-owned read model for bed-to-VRecorder assignments "
                "and relationship anomalies"
            ),
        ],
        relative(swift_capabilities_path): [
            "public var canUseLab: Bool",
            "canUseLab: Bool = true",
            "self.canUseLab = canUseLab",
        ],
        relative(pwa_client_path): [
            '"/runtime/lab/scenarios"',
            '"/runtime/lab/sessions"',
            "startLabRecorder(",
            "stopLabRecorder(",
            '"/runtime/lab/vital-files/replay"',
            '"/runtime/stack"',
            '/runtime/services/${encodeURIComponent(request.service)}/start',
            '/runtime/services/${encodeURIComponent(request.service)}/stop',
            '/runtime/services/${encodeURIComponent(request.service)}/restart',
            '"/runtime/vitaldb/recorders"',
            '"/runtime/vitaldb/beds"',
            '"/runtime/vitaldb/relationships"',
        ],
        relative(pwa_schema_path): [
            "capabilities: z.array(z.string())",
        ],
        relative(pwa_advanced_path): [
            "useRuntimeStack",
            "useRuntimeServiceResources",
            'stackStatus.state !== "loaded"',
            "Runtime stack status is",
            "Failed to read Runtime product services",
        ],
        relative(pwa_hooks_path): [
            "export function useRuntimeStack()",
            "runtimeControlGateway.getRuntimeStack()",
            "export function useRuntimeServiceResources(services: string[])",
            "runtimeControlGateway.getGuestServiceResource(service)",
        ],
        relative(pwa_lab_page_path): [
            "useControlCapabilities",
            "capabilities.data?.canUseLab",
            "capabilities.data?.canListLabSessions",
            "capabilities.data?.canControlLabRecorders",
            "labCapability === true",
        ],
        relative(pwa_pages_test_path): [
            (
                "shows non-loaded Runtime stack status without treating it as "
                "an empty service list"
            ),
            (
                "keeps Product Lab visible but disables Lab commands when Lab "
                "capability is unavailable"
            ),
            'state: "failed"',
            "canUseLab: false",
            "Runtime stack status is failed.",
            "No Runtime product services are reported.",
        ],
    }
    forbidden = [
        "/dev/testkit",
        "RuntimeTestKit",
        "MacTestKit",
        "canUseTestTools",
        "Raw VitalDB observation snapshots remain the source of truth",
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
    matches.extend(
        f"{relative(pwa_advanced_path)}:{token}"
        for token in [
            "runtimeStatus?.guestServiceResources",
            "runtimeStatus?.guestServiceResourceReadIssues",
            "runtimeStatus.guestServiceStatuses",
            "runtimeStatus.guestServicesReadState",
        ]
        if token in texts[relative(pwa_advanced_path)]
    )
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


def check_guest_control_default_state_uses_sqlite_control_store() -> CheckResult:
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
        / "src/tirosh_guest_tools/adapters/outbound/sqlite_control/repository.py"
    )
    control_migrations_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/sqlite_control/migrations.py"
    )
    control_store_migration_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/control_store_migration.py"
    )
    control_store_cli_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/adapters/inbound/cli.py"
    )
    macos_control_service_path = (
        MACOS_RUNTIME
        / "Support/Guest/systemd/tirosh-vitalserver-guest-control-api.service"
    )
    linux_control_service_path = (
        ROOT
        / "apps/vitalserver-platform-agent/packaging/linux"
        / "vitalserver-runtime-controller.service"
    )
    default_control_store_settings_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/resources/guest-tools.toml"
    )
    linux_control_store_settings_path = (
        ROOT
        / "apps/vitalserver-platform-agent/packaging/linux"
        / "runtime-controller.toml"
    )
    hyperv_control_store_settings_path = (
        ROOT
        / "apps/vitalserver-platform-agent/packaging/windows/hyperv-guest"
        / "guest-tools.toml"
    )
    api_tests_path = GUEST_TOOLS / "tests/test_guest_control_api.py"
    usecase_tests_path = GUEST_TOOLS / "tests/test_guest_control_usecases.py"
    sqlite_tests_path = GUEST_TOOLS / "tests/test_guest_control_sqlite_repository.py"
    lab_settings_path = ROOT / "apps/vitalserver-lab/vitalserver_lab/settings.py"
    lab_server_path = ROOT / "apps/vitalserver-lab/vitalserver_lab/server.py"
    lab_sqlalchemy_store_path = (
        ROOT
        / "apps/vitalserver-lab/vitalserver_lab/persistence/sqlalchemy_store.py"
    )
    lab_records_path = (
        ROOT / "apps/vitalserver-lab/vitalserver_lab/persistence/records.py"
    )
    lab_mappers_path = (
        ROOT / "apps/vitalserver-lab/vitalserver_lab/persistence/mappers.py"
    )
    lab_tests_path = ROOT / "apps/vitalserver-lab/tests/test_server.py"
    lab_sqlalchemy_tests_path = (
        ROOT / "apps/vitalserver-lab/tests/test_sqlalchemy_store.py"
    )
    lab_readme_path = ROOT / "apps/vitalserver-lab/README.md"
    compose_path = MACOS_RUNTIME / "Support/Guest/compose.yaml"
    api_text = read(api_path)
    runtime_text = read(runtime_path)
    usecase_text = read(usecase_path)
    operation_artifact_sink_text = read(operation_repository_path)
    api_tests_text = read(api_tests_path)
    usecase_tests_text = read(usecase_tests_path)
    control_migrations_text = read(control_migrations_path)
    control_store_migration_text = read(control_store_migration_path)
    control_store_cli_text = read(control_store_cli_path)
    macos_control_service_text = read(macos_control_service_path)
    linux_control_service_text = read(linux_control_service_path)
    default_control_store_settings_text = read(default_control_store_settings_path)
    linux_control_store_settings_text = read(linux_control_store_settings_path)
    hyperv_control_store_settings_text = read(hyperv_control_store_settings_path)
    sqlite_tests_text = read(sqlite_tests_path)
    lab_settings_text = read(lab_settings_path)
    lab_server_text = read(lab_server_path)
    lab_sqlalchemy_store_text = read(lab_sqlalchemy_store_path)
    lab_records_text = read(lab_records_path)
    lab_mappers_text = read(lab_mappers_path)
    lab_tests_text = read(lab_tests_path)
    lab_sqlalchemy_tests_text = read(lab_sqlalchemy_tests_path)
    lab_readme_text = read(lab_readme_path)
    compose_text = read(compose_path)
    required = {
        relative(api_path): [
            "SQLiteControlRepository",
            "PostgresVitalDBReadModelRepository",
            'SETTINGS.paths.control_state_dir / "control.sqlite"',
            "operations.check_ready()",
            "operations=operations",
            "vitaldb_read_model=vitaldb_read_model",
            "usecases.recover_interrupted_operations()",
            "usecases.readiness()",
            "HTTPStatus.SERVICE_UNAVAILABLE",
            "HTTPStatus.CONFLICT",
            '"operationInProgress"',
        ],
        relative(usecase_path): [
            "def readiness(self) -> dict[str, object]:",
            "def recover_interrupted_operations(self) -> None:",
            "self._operations.check_ready",
            "def _required_readiness_dependency(",
            '"operationRepository"',
            "self._operations.record_accepted(",
            "self._operations.record_transition(operation)",
        ],
        relative(operation_repository_path): [
            "class SQLiteControlRepository",
            "def migrate_schema(self) -> None:",
            "def check_ready(self) -> None:",
            "def record_accepted(",
            "def record_transition(",
            "ActiveOperationLeaseRecord",
            'connection.exec_driver_sql("BEGIN IMMEDIATE")',
            "TERMINAL_OPERATION_STATES",
            "GUEST_CONTROL_OPERATION_LEASE_RESOURCE_KEY",
            'kind="operationLeaseConflict"',
            'kind="operationLeaseMissing"',
            "validate_control_schema(connection)",
        ],
        relative(control_migrations_path): [
            "def migrate_control_schema(connection: Connection) -> None:",
            "def validate_control_schema(connection: Connection) -> None:",
            "MigrationContext",
            "Operations",
            '"service_operations"',
            '"service_operation_events"',
            '"active_operation_leases"',
        ],
        relative(control_store_migration_path): [
            "def migrate_control_store(",
            "control_store: ControlStoreSettings",
            "validate_control_store_location(control_store, control_state_dir)",
            "require_real_control_store_root(control_store)",
            'kind="controlStoreRootNotMounted"',
            "control_state_root_is_mounted",
            "repository.migrate_schema()",
            "repository.check_ready()",
        ],
        relative(control_store_cli_path): [
            "def guest_tools_migrate_control_store() -> int:",
            "control_store=SETTINGS.control_store",
        ],
        relative(macos_control_service_path): [
            "RequiresMountsFor=/mnt/runtime",
            "ExecStartPre=/opt/tirosh/guest-tools/venv/bin/"
            "tirosh-guest-tools-migrate-control-store",
        ],
        relative(linux_control_service_path): [
            "RequiresMountsFor=/var/lib/vitalserver",
            "ExecStartPre=/opt/vitalserver/current/runtime-controller/venv/bin/"
            "tirosh-guest-tools-migrate-control-store",
        ],
        relative(default_control_store_settings_path): [
            "[controlStore]",
            'root = "/mnt/runtime"',
            "requiresMount = true",
        ],
        relative(linux_control_store_settings_path): [
            "[controlStore]",
            'root = "/var/lib/vitalserver"',
            "requiresMount = false",
        ],
        relative(hyperv_control_store_settings_path): [
            "[controlStore]",
            'root = "/mnt/runtime"',
            "requiresMount = true",
        ],
        relative(api_tests_path): [
            "test_default_usecases_require_migrated_sqlite_without_postgres_startup",
            "test_ready_route_reports_control_store_dependency_failure",
            "test_ready_route_does_not_probe_configured_vitaldb",
            "test_active_control_lease_conflict_returns_explicit_conflict",
            'checks == ["sqlite"]',
        ],
        relative(usecase_tests_path): [
            "test_controller_recovery_marks_unfinished_operation_as_interrupted",
            "test_readiness_only_probes_required_control_dependencies",
            "test_readiness_preserves_control_store_failure",
            "test_service_command_lease_conflict_does_not_write_desired_state",
            "controllerRestarted",
        ],
        relative(sqlite_tests_path): [
            "test_sqlite_control_store_records_operation_event_and_lease_atomically",
            "test_sqlite_control_store_rolls_back_operation_event_and_lease_together",
            "test_sqlite_control_store_rejects_missing_required_table",
            "test_sqlite_control_store_rejects_concurrent_active_operation_lease",
            "test_sqlite_control_store_rejects_transition_without_matching_lease",
            "test_sqlite_control_store_rejects_invalid_runtime_event_history",
            "test_controller_restart_interrupts_unfinished_operation_and_releases_lease",
            'assert journal_mode(control_dir / "control.sqlite") == "wal"',
            'assert not (control_dir / "control.sqlite").exists()',
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
        relative(lab_sqlalchemy_store_path): [
            "class SQLAlchemyLabSessionStore",
            "create_engine(_sqlalchemy_url(database_url)",
            '"postgresql+psycopg://"',
            "LabRecordBase.metadata.create_all",
            'kind="labSessionStoreUnavailable"',
        ],
        relative(lab_records_path): [
            "class LabSessionRecord",
            "class LabBedRecord",
            "class LabRecorderRecord",
        ],
        relative(lab_mappers_path): [
            "def session_record(",
            "def session_domain(",
            "def bed_record(",
            "def bed_domain(",
            "def recorder_record(",
            "def recorder_domain(",
        ],
        relative(lab_tests_path): [
            "test_memory_session_store_requires_explicit_dev_override",
            "test_load_settings_reports_invalid_port_configuration",
            "test_load_settings_reports_non_positive_port_configuration",
            "LabSettingsConfigurationError",
            "allow_memory_store=False",
            "VITALSERVER_LAB_ALLOW_MEMORY_STORE",
        ],
        relative(lab_sqlalchemy_tests_path): [
            "test_sqlalchemy_store_uses_same_domain_contract_with_sqlite",
            "test_sqlalchemy_store_writes_existing_timestamp_columns",
        ],
        relative(lab_readme_path): [
            "Runtime v2 product service",
            "Guest Control `/runtime/lab/*`",
            "Runtime Control `/runtime/lab/*`",
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
        relative(operation_repository_path): operation_artifact_sink_text,
        relative(control_migrations_path): control_migrations_text,
        relative(control_store_migration_path): control_store_migration_text,
        relative(control_store_cli_path): control_store_cli_text,
        relative(macos_control_service_path): macos_control_service_text,
        relative(linux_control_service_path): linux_control_service_text,
        relative(default_control_store_settings_path): default_control_store_settings_text,
        relative(linux_control_store_settings_path): linux_control_store_settings_text,
        relative(hyperv_control_store_settings_path): hyperv_control_store_settings_text,
        relative(api_tests_path): api_tests_text,
        relative(usecase_tests_path): usecase_tests_text,
        relative(sqlite_tests_path): sqlite_tests_text,
        relative(lab_settings_path): lab_settings_text,
        relative(lab_server_path): lab_server_text,
        relative(lab_sqlalchemy_store_path): lab_sqlalchemy_store_text,
        relative(lab_records_path): lab_records_text,
        relative(lab_mappers_path): lab_mappers_text,
        relative(lab_tests_path): lab_tests_text,
        relative(lab_sqlalchemy_tests_path): lab_sqlalchemy_tests_text,
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
    for token in (
        "PostgresOperationRepository",
        "operations.ensure_schema()",
        "operations.migrate_schema()",
    ):
        if token in api_text:
            present.append(f"{relative(api_path)}:{token}")
    if "self._vitaldb_read_model.check_ready" in usecase_text:
        present.append(
            f"{relative(usecase_path)}:self._vitaldb_read_model.check_ready"
        )
    if "VITALSERVER_LAB_ALLOW_MEMORY_STORE" in compose_text:
        present.append(
            f"{relative(compose_path)}:VITALSERVER_LAB_ALLOW_MEMORY_STORE"
        )
    for path, value in (
        (control_store_cli_path, control_store_cli_text),
        (macos_control_service_path, macos_control_service_text),
        (linux_control_service_path, linux_control_service_text),
    ):
        if "--control-state-dir" in value:
            present.append(f"{relative(path)}:--control-state-dir")
    if missing or present:
        return CheckResult(
            "guest-control-default-state-sqlite-control-store",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "guest-control-default-state-sqlite-control-store",
        True,
        "Guest Control API defaults to a Guest-owned SQLite control store; "
        "Postgres remains the VitalDB read model and Product Lab dependency",
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
            "self._service_status_snapshots.save_service_status_snapshot(service_status)",
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
        "through the service status snapshot repository after successful commands",
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
    ports_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/application/guest_control/ports.py"
    )
    repository_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/sqlite_control"
        / "repository.py"
    )
    api_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    swift_health_details_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies"
        / "RuntimeStatusHealthDetailsPolicy.swift"
    )
    swift_advanced_health_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Policies"
        / "RuntimeStatusAdvancedServiceHealthPolicy.swift"
    )
    swift_display_tests_path = (
        MACOS_RUNTIME
        / "Tests/MacControlPanelHostTests/RuntimeStatusDisplayPolicyTests.swift"
    )
    swift_endpoint_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpoint.swift"
    )
    swift_endpoint_routing_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpointRouting.swift"
    )
    swift_http_types_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlHTTPTypes.swift"
    )
    swift_read_routes_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlHTTPReadRoutes.swift"
    )
    swift_client_handler_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlClientAPIReadHandler.swift"
    )
    swift_client_contracts_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeClientContracts.swift"
    )
    swift_command_worker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
        / "MacRuntimeControlCommandWorker.swift"
    )
    swift_client_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Client"
        / "MacRuntimeControlClient.swift"
    )
    swift_api_tests_path = (
        MACOS_RUNTIME
        / "Tests/InboundAdaptersTests/RuntimeControlAPI/RuntimeControlAPITests.swift"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    pwa_types_path = (
        PWA
        / "src/domain/runtime-control/contracts/runtimeControlTypes.ts"
    )
    pwa_schemas_path = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    pwa_gateway_path = PWA / "src/console/runtimeControlGateway.ts"
    pwa_api_client_path = (
        PWA
        / "src/infrastructure/console-api/runtimeControlApiClient.ts"
    )
    pwa_api_client_tests_path = (
        PWA
        / "src/infrastructure/console-api/runtimeControlApiClient.test.ts"
    )
    pwa_advanced_page_path = (
        PWA / "src/pages/advanced/AdvancedPage.tsx"
    )
    pwa_pages_tests_path = (
        PWA / "src/pages/pages.test.tsx"
    )
    swift_status_assembly_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeStatusAssembly.swift"
    )
    swift_status_contract_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlModels.swift"
    )
    swift_status_contract_tests_path = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    swift_status_assembly_tests_path = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlStatusAssemblerTests.swift"
    )
    swift_observation_health_policy_path = (
        MACOS_RUNTIME
        / "Sources/Domain/Policies/RuntimeObservationHealthPolicy.swift"
    )
    swift_runtime_health_checker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Health/RuntimeHealthChecker.swift"
    )
    swift_health_evaluator_tests_path = (
        MACOS_RUNTIME
        / "Tests/DomainTests/Policies/RuntimeHealthEvaluatorTests.swift"
    )
    swift_recovery_planner_tests_path = (
        MACOS_RUNTIME
        / "Tests/DomainTests/Policies/RuntimeRecoveryPlannerTests.swift"
    )
    swift_health_evaluator_path = (
        MACOS_RUNTIME / "Sources/Domain/Policies/RuntimeHealthEvaluator.swift"
    )
    swift_health_snapshot_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeHealthSnapshot.swift"
    )
    swift_health_reads_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeHealthObservationReads.swift"
    )
    swift_recovery_planner_path = (
        MACOS_RUNTIME / "Sources/Domain/Policies/RuntimeRecoveryPlanner.swift"
    )
    swift_watchdog_policy_path = (
        MACOS_RUNTIME / "Sources/Domain/Policies/RuntimeWatchdogRecoveryPolicy.swift"
    )
    swift_watchdog_runner_path = (
        MACOS_RUNTIME / "Sources/Workflow/RuntimeWatchdog/RuntimeWatchdogRunner.swift"
    )
    swift_watchdog_usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeHealth/WatchdogRuntimeUseCase.swift"
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
        relative(ports_path): [
            "class ServiceStatusSnapshotRepository",
            "class GuestServiceResourceRepository",
            "class OperationRepository",
        ],
        relative(usecases_path): [
            "def get_guest_service_resource(",
            "def observe_guest_service(",
            "def update_guest_service_spec(",
            "def reconcile_guest_service(",
            "service_status_snapshots: ServiceStatusSnapshotRepository",
            "guest_service_resources: GuestServiceResourceRepository",
            "self._save_guest_service_spec(",
            "reconcile_guest_service(",
            "_guest_service_observed_state(",
            "self._service_status_snapshots.save_service_status_snapshot",
            "self._guest_service_resources.save_guest_service_resource(resource)",
            "self._guest_service_resources.get_guest_service_resource",
            "final_decision = reconcile_guest_service(",
            "conditions=final_decision.conditions",
        ],
        relative(repository_path): [
            "GuestServiceResourceRecord",
            "def save_guest_service_resource(",
            "def get_guest_service_resource(",
            "guest_service_resource_from_record",
        ],
        relative(api_path): [
            'parts[3] == "resource"',
            'parts[3] == "spec"',
            'parts[3] == "observe"',
            'parts[3] == "reconcile"',
            "def do_PUT(self) -> None:",
        ],
        relative(swift_health_details_path): [
            "resources.first",
            "resourceReadIssues.first",
            '"spec \\(resource.spec.state)"',
            '"desired \\(desiredState)"',
            '"status \\(resource.status.state)"',
            '"observed \\(observedState)"',
            '"status read failed \\(readError.kind): \\(readError.message)"',
            "resource.conditions",
            "joined(separator: \"; \")",
            '"conditions \\(conditionText)"',
            '"last operation \\(lastOperationId)"',
        ],
        relative(swift_advanced_health_path): [
            "resources.first",
            "resourceReadIssues.first",
            '"spec \\(resource.spec.state)"',
            '"desired \\(desiredState)"',
            '"status \\(resource.status.state)"',
            '"observed \\(observedState)"',
            '"status read failed \\(readError.kind): \\(readError.message)"',
            "resource.conditions",
            "joined(separator: \"; \")",
            '"conditions \\(conditionText)"',
            '"last operation \\(lastOperationId)"',
        ],
        relative(pwa_advanced_page_path): [
            "resource?.spec.state",
            "resource?.spec.desiredState",
            "resource?.status.readError",
            "resource.status.readError.kind",
            "resource.status.readError.message",
            "resource?.status.state",
            "resource?.status.observedState",
            "resource.conditions",
            ".join(\"; \")",
            "resource?.lastOperationId",
            'header: "Spec"',
            'header: "Status read"',
            'header: "Conditions"',
            'header: "Last operation"',
        ],
        relative(tests_path): [
            "test_guest_service_resource_get_is_side_effect_free",
            "test_observe_guest_service_reads_and_persists_loaded_status",
            "test_guest_service_controller_rejects_unknown_service",
            "test_guest_service_spec_update_rejects_invalid_desired_state",
            "test_guest_service_spec_update_persists_desired_state",
            "test_observe_guest_service_uses_explicit_status_and_resource_repositories",
            "test_reconcile_guest_service_without_spec_is_blocked",
            'resource.status.as_json()["observedState"] == "stopped"',
            'resource.conditions[0].reason == "DesiredStateObserved"',
        ],
        relative(policy_tests_path): [
            "test_reconcile_blocks_missing_spec",
            "test_reconcile_blocks_failed_status_read",
            "test_reconcile_noops_when_desired_running_is_observed",
            "test_reconcile_restarts_when_restart_is_requested",
        ],
        relative(swift_display_tests_path): [
            "spec configured | desired running | status loaded | observed running",
            "conditions Reconciled=true DesiredStateObserved",
            "ResourceFresh=true ObservedRecently",
            "last operation op-",
            "Resource read failed: resource document decode failed",
            "Resource read failed: resource controller unavailable",
        ],
        relative(swift_endpoint_path): [
            "case guestServiceResource",
        ],
        relative(swift_endpoint_routing_path): [
            'path: "/runtime/services/{service}/resource"',
            "case .guestServiceResource:",
            'expectedAction = "resource"',
        ],
        relative(swift_http_types_path): [
            "func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource",
        ],
        relative(swift_read_routes_path): [
            "case .guestServiceResource:",
            "handler.guestServiceResource(try request.runtimeGuestServiceName())",
        ],
        relative(swift_client_handler_path): [
            "try await client.guestServiceResource(service)",
        ],
        relative(swift_client_contracts_path): [
            "func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource",
            '"guest-service-resource"',
        ],
        relative(swift_command_worker_path): [
            "func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource",
            "try gateway.serviceResource(service)",
        ],
        relative(swift_client_path): [
            "func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource",
            "try await commandWorker.guestServiceResource(service)",
        ],
        relative(swift_api_tests_path): [
            'path: "/runtime/services/recorder-ingress/resource"',
            "client.guestServiceResourceRequests",
            "func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource",
        ],
        relative(openapi_path): [
            '"/runtime/services/{service}/resource"',
            '"operationId": "getRuntimeGuestServiceResource"',
            '"$ref": "#/components/schemas/RuntimeGuestServiceResource"',
        ],
        relative(pwa_types_path): [
            "export type RuntimeGuestServiceResource",
            'components["schemas"]["RuntimeGuestServiceResource"]',
        ],
        relative(pwa_schemas_path): [
            "export const runtimeGuestServiceResourceSchema",
        ],
        relative(pwa_gateway_path): [
            "getGuestServiceResource(service: string): Promise<RuntimeGuestServiceResource>",
        ],
        relative(pwa_api_client_path): [
            "runtimeGuestServiceResourceSchema",
            "`/runtime/services/${encodeURIComponent(service)}/resource`",
        ],
        relative(pwa_api_client_tests_path): [
            '"/runtime/services/app/resource"',
            'client.getGuestServiceResource("app")',
            'lastOperationId: "op-app"',
        ],
        relative(pwa_pages_tests_path): [
            'name: "Spec"',
            'name: "Status read"',
            'name: "Conditions"',
            'name: "Last operation"',
            "serviceStatusReadFailed: docker inspect failed",
            "scheduler Not reported Not reported configured Not reported loaded Not reported",
            "Reconciled=true DesiredStateObserved: matched desired state; ResourceFresh=true ObservedRecently: resource observation is current",
            "op-app-1",
            "op-worker-2",
        ],
        relative(swift_status_assembly_path): [
            "public enum PlatformStateAssembler",
            "private static func currentFailureReasons(",
        ],
        relative(swift_status_assembly_tests_path): [
            "testMakeStatusDoesNotAggregateRuntimeStackState",
            "guestServiceObservationReadFailed",
        ],
        relative(swift_status_contract_path): [
            "public struct PlatformState:",
            "public var dataStorage: ResourceUsage?",
            "case dataStorage",
        ],
        relative(swift_status_contract_tests_path): [
            "testPlatformStateRoundTripsExplicitCurrentFieldsThroughJSON",
            'XCTAssertFalse(encodedText.contains("guestService"))',
            'XCTAssertFalse(encodedText.contains("cpuUsagePercent"))',
            'XCTAssertFalse(encodedText.contains("systemDisk"))',
        ],
        relative(swift_observation_health_policy_path): [
            "isOperatorVisibleOnlyAnomaly",
        ],
        relative(swift_runtime_health_checker_path): [
            "public func observationReads() -> RuntimeHealthObservationReads",
        ],
        relative(swift_health_evaluator_path): [
            "public struct RuntimeHealthInput",
        ],
        relative(swift_health_snapshot_path): [
            "public struct RuntimeHealthSnapshot",
        ],
        relative(swift_health_reads_path): [
            "public struct RuntimeHealthObservationReads",
        ],
        relative(swift_recovery_planner_path): [
            "public enum RuntimeRecoveryPlanner",
        ],
        relative(swift_watchdog_policy_path): [
            "public enum RuntimeWatchdogRecoveryPolicy",
        ],
        relative(swift_watchdog_runner_path): [
            "public struct RuntimeWatchdogActions",
        ],
        relative(swift_watchdog_usecase_path): [
            "watchdog platform recovery plan",
        ],
        relative(swift_health_evaluator_tests_path): [
            "testHealthyInputHasNoFailureReasons",
        ],
        relative(swift_recovery_planner_tests_path): [
            "testRuntimeReadinessFailureRestartsPlatformVMAndProxy",
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
        relative(usecases_path): [
            "self._operations.save_service_status_snapshot",
            "self._operations.save_guest_service_resource",
            "self._operations.get_guest_service_resource",
        ],
        relative(swift_health_details_path): [
            "resource.conditions.first",
            "status.guestServicesReadState",
            "status.guestServiceStatuses",
            "status.guestServiceResources",
            "status.guestServiceResourceReadIssues",
            "status.guestStackProbeErrors",
        ],
        relative(swift_advanced_health_path): [
            "resource.conditions.first",
            "status.guestServicesReadState",
            "status.guestServiceStatuses",
            "status.guestServiceResources",
            "status.guestServiceResourceReadIssues",
            "status.guestStackProbeErrors",
            "runtimeStatus.guestService",
        ],
        relative(pwa_advanced_page_path): [
            "resource.conditions[0]",
            "resource?.spec.desiredState ?? resource?.spec.state",
            "resource?.status.observedState ??\n                resource?.status.state",
            'row.resourceIssue || "OK"',
        ],
        relative(swift_status_assembly_path): [
            "guestServicesRead.statuses.compactMap(guestServiceFailureReason)",
            "RuntimeGuestServicesRead",
            "guestServiceFailureReasons",
            "guestServiceResourceReadIssues",
            "guestStackProbeErrors",
        ],
        relative(swift_runtime_health_checker_path): [
            "try? gateway.serviceResource(service.service)",
            "guestServiceHealthRead(",
            "gateway.stackStatus()",
            "gateway.serviceResource(",
        ],
        relative(swift_observation_health_policy_path): [
            "guestService",
            "requiresGuestStackReconcile",
        ],
        relative(swift_health_evaluator_path): ["guestService"],
        relative(swift_health_snapshot_path): ["guestService"],
        relative(swift_health_reads_path): ["guestService"],
        relative(swift_recovery_planner_path): [
            "guestService",
            "reconcileGuestStack",
        ],
        relative(swift_watchdog_policy_path): [
            "guestService",
            "reconcileGuestStack",
        ],
        relative(swift_watchdog_runner_path): ["reconcileGuestStack"],
        relative(swift_watchdog_usecase_path): [
            "guestStackReconcile",
            "reconcileGuestStack",
        ],
        relative(swift_health_evaluator_tests_path): [
            "guestServiceStatuses",
            "guestServiceResources",
            "guestServiceResourceReadIssues",
        ],
        relative(swift_recovery_planner_tests_path): [
            "reconcileGuestStack",
            "guestServiceStatuses",
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
        "stores explicit resource state in Guest-owned SQLite, and keeps reconcile policy pure",
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
            "'SQLAlchemy==2.0.51'",
            "'psycopg[binary]==3.3.4'",
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
        ROOT / "docs/runtime/runtime-control.openapi.json",
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
            ".disabled(!viewModel.labCanStartSelectedSession)",
            ".disabled(!viewModel.labCanStopSelectedSession)",
            "viewModel.selectedLabSession?.state != .running",
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
    required = {
        PWA / "src/infrastructure/console-api/runtimeControlApiClient.ts": [
            'available.has("services:start")',
            'available.has("services:stop")',
            'available.has("services:restart")',
            "canControlGuestServices:",
        ],
        GUEST_TOOLS / "src/tirosh_guest_tools/application/guest_control/usecases.py": [
            '"services:start"',
            '"services:stop"',
            '"services:restart"',
        ],
        PWA / "src/pages/advanced/AdvancedPage.tsx": [
            "capabilities.data?.canControlGuestServices",
        ],
    }
    missing = {
        relative(path): [token for token in tokens if token not in read(path)]
        for path, tokens in required.items()
        if any(token not in read(path) for token in tokens)
    }
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
            'path: "/runtime/capabilities"',
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
        "RuntimeGuestDocumentLoadResult<GuestRuntimeObservationDocument>",
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
        "Guest capability checks consume Guest Control /runtime/capabilities",
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
            'path: "/runtime/services"',
            'path: "/runtime/stack"',
            'path: "/runtime/vitaldb/observations/latest"',
            'path: "/runtime/vitaldb/relationships"',
            'path: "/runtime/lab/scenarios"',
            'path: "/runtime/lab/vital-files/replay"',
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


def check_cli_guest_control_default_url_uses_guest_address_provider() -> CheckResult:
    lifecycle_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeLifecycle.swift"
    )
    lifecycle_composition_path = (
        MACOS_RUNTIME
        / "Sources/Bootstrap/DI"
        / "RuntimeLifecycleComposition.swift"
    )
    service_support_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Support"
        / "RuntimeLifecycle+ServiceSupport.swift"
    )
    lifecycle_text = read(lifecycle_path)
    lifecycle_composition_text = read(lifecycle_composition_path)
    text = read(service_support_path)
    required = [
        "let guestAddressProvider: any RuntimeGuestAddressProvider",
        "self.guestAddressProvider = container.guestAddressProvider",
        "guestAddressProvider ?? FileRuntimeGuestAddressResourceStore(",
        "documentURL: installedPaths.runtimeEndpoint",
        "readGuestAddress()",
        "guestAddressRead.loadedAddress",
        "guestAddressRead.failureStatusText",
        "guestControlAPIBaseURL(vmIP: vmIP)",
        '"http://\\(vmIP):18330"',
    ]
    forbidden = [
        "RuntimeGuestAddressOwnerProvider",
        "RuntimeBootstrapGuestAddressProvider.live(",
        "RuntimeVMIPFileGuestAddressProvider(",
        "vmIPFile: installedPaths.vmIPFile",
        "JSONFileRuntimeStatusArtifactSink(",
        "installedPaths.runtimeStatus",
        "document.vmIP",
        "document.guestAddressRead",
        "runtime status document is missing",
        "runtime status read failed",
        "GuestRuntimeObservationDocument",
        "installedPaths.runtimeObservation",
        "runtimeStateVMIP",
        "try?",
    ]
    combined = lifecycle_text + "\n" + lifecycle_composition_text + "\n" + text
    missing = [token for token in required if token not in combined]
    present = [token for token in forbidden if token in text]
    if "RuntimeBootstrapGuestAddressProvider.live(" in lifecycle_composition_text:
        present.append("RuntimeLifecycleComposition:RuntimeBootstrapGuestAddressProvider.live(")
    if "RuntimeControlAPIGuestAddressProvider()" in lifecycle_composition_text:
        present.append("RuntimeLifecycleComposition:RuntimeControlAPIGuestAddressProvider()")
    if missing or present:
        return CheckResult(
            "cli-guest-control-default-url-guest-address",
            False,
            (
                f"missing={missing} forbidden_present={present} "
                f"path={relative(service_support_path)}"
            ),
        )
    return CheckResult(
        "cli-guest-control-default-url-guest-address",
        True,
        "CLI derives the default Guest Control URL from explicit Guest address reads",
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
            "guest runtime-observation.json\n  -> watchdog/runtime",
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
        "Guest Control `/runtime/lab/*`",
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
            "runtime-observation.json, result JSON, guest logs",
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
            "active operation이 `Installing`",
        ],
        "site-docs/release/runtime-status.md": [
            "guest runtime-state의 `containerServices` 계약",
            "containerObservation.composeServicesReadState",
            "prepare-update-shutdown.request",
            "prepare-update-shutdown-result.json",
            "Guest shutdown request는 single-shot contract",
            "request file을 poweroff 직전까지",
            "해당 active operation 상태",
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
            "Product Lab 기능은 `/runtime/lab/*` Runtime Control API 계약으로만 노출",
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
            "Runtime Control `/runtime/lab/*`, Guest Control `/runtime/lab/*`, "
            "`apps/vitalserver-lab`",
            "Guest Control update activation operation을 생성",
        ],
        "docs/adr/0002-helper-client-boundary-for-local-and-remote-runtime.md": [
            "`/runtime/*`, `/runtime/vitaldb/*`, `/host/*`, `/runtime/lab/*`",
            "Legacy `/dev/testkit/*` route는 Runtime v2 product surface가 아니며",
            "Product Lab 계약으로 노출한다",
        ],
        "docs/recorder/vital-recorder-integration.md": [
            "Helper Product Lab 경로",
            "Runtime Control API `/runtime/lab/*`",
            "Guest Control API `/runtime/lab/*`",
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
            "`/runtime/operations/{operationId}`",
        ],
        "site-docs/dev/repository-map.md": [
            "Product Lab 수정",
            "`apps/vitalserver-lab`, Runtime Control `/runtime/lab/*`, "
            "Guest Control `/runtime/lab/*`",
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
            "Active operation은 별도 operation-state read model이 제공하는 작업 소유권 표시",
            "Runtime Control status, operation-state, event",
        ],
        "site-docs/release/runtime-status.md": [
            "Guest Control API가 제공하는 service/stack status 계약",
            "Guest Control update-shutdown operation",
            "Guest shutdown command는 single-shot operation",
            "Active operation은 operation-state owner가 제공하며",
        ],
        "docs/troubleshooting/070_golden-disk-runtime-boot-proof-gap.md": [
            "Product Lab 또는 다른 required product service",
            "Guest Control `/runtime/stack` 응답",
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


def check_delivery_validation_docs_do_not_promote_legacy_runtime_state_files(
) -> CheckResult:
    path = ROOT / "site-docs/dev/delivery-validation.md"
    text = read(path)
    required = [
        "Host의 mutating runtime operation owner는 Runtime Control Host operation lease API입니다.",
        "`runtime-operation-lease.json`은 diagnostics/export",
        "artifact로 남을 수 있지만 active operation ownership의 source of truth가 아닙니다.",
        "workflow state artifact는 diagnostics/export evidence로만 남길 수 있습니다.",
        "workflow artifact를 source of truth로 사용하지 말고 typed owner contract를",
        "Guest Control readiness/service status",
        "runtime smoke phase가 소유",
    ]
    forbidden = [
        "Host의 mutating runtime operation은 `runtime-operation-lease.json`을 source of truth로 사용합니다.",
        "Lease acquire, heartbeat, release는 파일 lock으로 보호되어야 하며",
        "operation 상태는 lease document, Guest Control operation document, workflow state document",
        "workflow state document로 명시되어야",
        "Guest bootstrap 완료, `runtime-observation.json` 생성, systemd/docker/http",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if missing or present:
        return CheckResult(
            "delivery-validation-docs-no-legacy-runtime-state-files",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "delivery-validation-docs-no-legacy-runtime-state-files",
        True,
        "delivery validation docs point operation ownership and runtime proof at owner APIs",
    )


def check_runtime_update_docs_do_not_promote_status_files_as_current_owners(
) -> CheckResult:
    checks = {
        ROOT / "docs/runtime/macos/update.md": {
            "required": [
                "explicit runtime health owner reads report healthy",
                "`runtime-status.json` may only mirror this as diagnostics projection",
                "diagnostics/status projection으로 갱신. current operation/health owner가 아님",
                "Guest Control/Postgres read model 갱신",
                "publish diagnostics/status projection",
            ],
            "forbidden": [
                "health passed | `runtime-status.json` state `healthy`",
                "runtime status | `status/runtime-status.json` | update/rollback 상태로 갱신",
                "guest activation | VM 내부에서 Docker image load, compose recreate, runtime-state 갱신",
                "write runtime status",
                "-> runtime-state 갱신",
            ],
        },
        ROOT / "docs/troubleshooting/067_initial-install-watchdog-degraded.md": {
            "required": [
                "install workflow/operation-state owner가 제공한 explicit state",
                "`runtime-status.json`은 diagnostics/status projection이며 current operation owner가 아닙니다.",
            ],
            "forbidden": [
                "초기 설치 상태는 install workflow가 작성한 `runtime-status.json` contract로만 판단합니다.",
            ],
        },
        ROOT / "docs/troubleshooting/073_installed-bootstrap-missing-rootfs-input-metadata.md": {
            "required": [
                "Older diagnostics/status projections can show `vm-runtime-state-missing`",
                "Current Runtime Control status must come from explicit owner reads",
                "rather than treating `runtime-status.json` as the failure owner",
            ],
            "forbidden": [
                "`runtime-status.json` can show `vm-runtime-state-missing`",
            ],
        },
        ROOT / "docs/troubleshooting/054_helper-message-log-stale-session-history.md": {
            "required": [
                "Use Runtime Control status as the current install state source",
                "`runtime-status.json` as diagnostics/export evidence only",
            ],
            "forbidden": [
                "Use `runtime-status.json`, Runtime Control status, install logs, command logs, and runtime events to diagnose the current install.",
            ],
        },
    }
    missing: list[str] = []
    present: list[str] = []
    for path, tokens in checks.items():
        text = read(path)
        missing.extend(
            f"{relative(path)}:{token}"
            for token in tokens["required"]
            if token not in text
        )
        present.extend(
            f"{relative(path)}:{token}"
            for token in tokens["forbidden"]
            if token in text
        )
    if missing or present:
        return CheckResult(
            "runtime-update-docs-no-status-file-current-owner",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "runtime-update-docs-no-status-file-current-owner",
        True,
        "runtime update and initial-install docs keep status/progress files as diagnostics artifacts",
    )


def check_runtime_event_history_docs_do_not_promote_files_as_state_owners(
) -> CheckResult:
    observability_path = ROOT / "docs/runtime/macos/observability.md"
    operation_contract_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeOperationEventContracts.swift"
    )
    request_parser_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlHTTPRequestParsing.swift"
    )
    read_routes_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlHTTPReadRoutes.swift"
    )
    guest_gateway_path = (
        MACOS_RUNTIME / "Sources/Application/Ports/RuntimeGuestControlGateway.swift"
    )
    pwa_gateway_path = PWA / "src/console/runtimeControlGateway.ts"
    pwa_client_path = (
        PWA / "src/infrastructure/console-api/runtimeControlApiClient.ts"
    )
    pwa_client_tests_path = (
        PWA / "src/infrastructure/console-api/runtimeControlApiClient.test.ts"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    api_tests_path = (
        MACOS_RUNTIME
        / "Tests/InboundAdaptersTests/RuntimeControlAPI/RuntimeControlAPITests.swift"
    )
    operation_contract_tests_path = (
        MACOS_RUNTIME / "Tests/ContractsTests/ContractsTests.swift"
    )
    swift_read_models = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlReadModels.swift"
    )
    swift_contract_tests = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    text = read(observability_path)
    swift_read_models_text = read(swift_read_models)
    swift_contract_tests_text = read(swift_contract_tests)
    required = [
        "Guest SQLite control ledger + Runtime Control `/runtime/events` "
        "`RuntimeOperationEventHistory`",
        "Host `runtime-events.jsonl`과 `runtime-observability.sqlite`는 이 API의 "
        "source나 successful fallback이 아닙니다.",
        "Guest Control `/runtime/events`는 이 index를 읽지 않고 Guest-owned "
        "`control.sqlite` operation ledger를 읽습니다.",
        "`RuntimeOperationEventQuery`/`RuntimeOperationEventType` public contract",
        "Host proxy와 PWA는 cursor 형식을 해석하거나 재작성하지 않고 "
        "Guest token을 그대로 전달하며, 형식 검증은 Guest ledger의 책임이다.",
        "Host diagnostics `RuntimeEventHistory.readError`",
        "operational event diagnostics artifact",
        "current `failureReasons`는 explicit owner reads에서 조립",
        "JSONL append를 durable diagnostics artifact",
    ]
    forbidden = [
        "`runtime-events.jsonl`은 runtime operational event의 1차 SoT입니다.",
        "SQLite read model은 조회용 index이므로 JSONL rotation이 있더라도 event SoT 역할을 대신하지 않습니다.",
        "Runtime event log | `runtime-observability.sqlite`, fallback `runtime-events.jsonl`",
        "/runtime/events via SQLite first, JSONL fallback",
        "`/runtime/events` read path는 SQLite index를 우선 사용하고 "
        "실패 시 JSONL",
        "JSONL fallback",
        "fallback으로 응답",
        "read model fallback",
        "`RuntimeEventHistoryOwnerReader` over `status/runtime-events.jsonl` and SQLite index",
        "| `runtime-events.jsonl` | runtime/watchdog | 제품 상태 이벤트 | Yes, through `RuntimeEventHistoryOwnerReader` |",
        "불가능하면 JSONL에서 읽은 최근 event history",
        "SQLite read model을 우선 사용하고, 불가능하면 JSONL",
        "| 언제 상태가 바뀌었나? | `runtime-observability.sqlite`, fallback `runtime-events.jsonl`, API `/runtime/events` |",
        "장애로 판단되면 `failureReasons`와 `runtime-events.jsonl`에 제품 용어로 기록합니다.",
        "JSONL append를 canonical source",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    operation_texts = {
        relative(operation_contract_path): read(operation_contract_path),
        relative(request_parser_path): read(request_parser_path),
        relative(read_routes_path): read(read_routes_path),
        relative(guest_gateway_path): read(guest_gateway_path),
        relative(pwa_gateway_path): read(pwa_gateway_path),
        relative(pwa_client_path): read(pwa_client_path),
        relative(pwa_client_tests_path): read(pwa_client_tests_path),
        relative(openapi_path): read(openapi_path),
        relative(api_tests_path): read(api_tests_path),
        relative(operation_contract_tests_path): read(operation_contract_tests_path),
    }
    operation_required = {
        relative(operation_contract_path): [
            "public struct RuntimeOperationEventQuery",
            "public enum RuntimeOperationEventType",
            "public struct RuntimeOperationEventHistory",
            "public let eventType: RuntimeOperationEventType?",
            "events = try container.decode([RuntimeOperationEventDocument].self, "
            "forKey: .events)",
            "guard container.contains(.nextCursor)",
            "guard container.contains(.matchingCount)",
            "try container.encodeNil(forKey: .nextCursor)",
            "try container.encodeNil(forKey: .matchingCount)",
        ],
        relative(request_parser_path): [
            "func runtimeOperationEventQuery() throws -> RuntimeOperationEventQuery",
            "RuntimeOperationEventQuery.maximumLimit",
            "RuntimeOperationEventType(rawValue: rawEventType)",
            "let cursor = try queryValue(named: \"cursor\")",
        ],
        relative(read_routes_path): [
            "let query = try request.runtimeOperationEventQuery()",
            "handler.loadRuntimeOperationEvents(query: query)",
        ],
        relative(guest_gateway_path): [
            "func runtimeEvents(query: RuntimeOperationEventQuery)",
        ],
        relative(pwa_gateway_path): [
            "type?: RuntimeEventTypeValue;",
        ],
        relative(pwa_client_path): [
            "runtimeEventTypeValues.includes(value as RuntimeEventTypeValue)",
        ],
        relative(pwa_client_tests_path): [
            "rejects non-operation event types before requesting the Guest ledger",
        ],
        relative(openapi_path): [
            "Read Guest Runtime Controller operation event history",
            '"operation-interrupted"',
        ],
        relative(api_tests_path): [
            "testRuntimeEventsEndpointRejectsLimitAboveGuestContractMaximum",
            "testRuntimeEventsEndpointForwardsOpaqueCursor",
            "testRuntimeEventsEndpointRejectsHostDiagnosticsEventType",
            "testRuntimeEventsEndpointPreservesGuestQueryRejectionAsBadRequest",
            "RuntimeOperationEventQuery(",
        ],
        relative(operation_contract_tests_path): [
            "testRuntimeOperationEventQueryKeepsGuestLedgerEventTypesSeparate",
            "testRuntimeOperationEventHistoryRequiresAndWrites"
            "ExplicitNullablePagination",
        ],
    }
    for path, tokens in operation_required.items():
        missing.extend(
            f"{path}:{token}"
            for token in tokens
            if token not in operation_texts[path]
        )
    operation_forbidden = {
        relative(request_parser_path): [
            "func runtimeOperationEventQuery() throws -> RuntimeEventQuery",
            'parts[0] == "event"',
        ],
        relative(guest_gateway_path): [
            "func runtimeEvents(query: RuntimeEventQuery)",
        ],
    }
    present.extend(
        f"{path}:{token}"
        for path, tokens in operation_forbidden.items()
        for token in tokens
        if token in operation_texts[path]
    )
    try:
        openapi = json.loads(operation_texts[relative(openapi_path)])
        operation_event_types = (
            openapi["components"]["schemas"]["RuntimeEventType"]["enum"]
        )
    except (KeyError, TypeError, json.JSONDecodeError):
        missing.append("OpenAPI.RuntimeEventType.operation-event-enum")
    else:
        if operation_event_types != [
            "operation-accepted",
            "operation-running",
            "operation-completed",
            "operation-failed",
            "operation-cancelled",
            "operation-interrupted",
        ]:
            missing.append("OpenAPI.RuntimeEventType.operation-event-enum")
    for label, token in [
        (
            "RuntimeEventHistory.required-events-array",
            "events = try container.decode([RuntimeEventDocument].self, forKey: .events)",
        ),
        (
            "RuntimeEventHistory.required-nullable-next-cursor",
            "nextCursor = try container.decodeRequiredNullable(String.self, forKey: .nextCursor)",
        ),
        (
            "RuntimeEventHistory.required-nullable-matching-count",
            "matchingCount = try container.decodeRequiredNullable(Int.self, forKey: .matchingCount)",
        ),
        (
            "RuntimeEventHistory.explicit-null-next-cursor",
            "try container.encodeNil(forKey: .nextCursor)",
        ),
    ]:
        if token not in swift_read_models_text:
            missing.append(label)
    if "testRuntimeEventHistoryRequiresEventsAndPaginationKeys" not in swift_contract_tests_text:
        missing.append("RuntimeControlContractsTests.required-event-history-document")
    for token in [
        "events = try container.decodeIfPresent([RuntimeEventDocument].self, forKey: .events) ?? []",
        "try container.encodeIfPresent(nextCursor, forKey: .nextCursor)",
        "try container.encodeIfPresent(matchingCount, forKey: .matchingCount)",
    ]:
        if token in swift_read_models_text:
            present.append(f"{relative(swift_read_models)}:{token}")
    if missing or present:
        return CheckResult(
            "runtime-event-history-docs-no-file-state-owner",
            False,
            f"missing={missing} forbidden_present={present} path={relative(observability_path)}",
        )
    return CheckResult(
        "runtime-event-history-docs-no-file-state-owner",
        True,
        "runtime event docs route product history through Runtime Control API/read model and keep files as diagnostics/index artifacts",
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
            "source: ${VITALSERVER_DOCS_DIR:-/mnt/tirosh/deploy/docs}",
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
            'screen.getByText("Access endpoints")',
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
    recorder_activity_troubleshooting_path = (
        ROOT / "docs/troubleshooting/031_recorder-activity-history-window.md"
    )
    texts = {
        relative(packaging_path): read(packaging_path),
        relative(observability_path): read(observability_path),
        relative(recorder_activity_troubleshooting_path): read(
            recorder_activity_troubleshooting_path
        ),
    }
    forbidden = {
        relative(packaging_path): [
            (
                "-> guest runtime-observation.json\n"
                "  -> watchdog\n"
                "  -> runtime-observability.sqlite\n"
                "  -> Runtime Control API /runtime/vitaldb/*"
            ),
        ],
        relative(observability_path): [
            (
                "-> vitaldb-observer snapshot\n"
                "  -> guest runtime-observation.json"
            ),
            "VitalDB observer snapshot",
            "compose service health summary를 recovery trigger와 연결",
            "원본 snapshot은 canonical source로 유지",
        ],
        relative(recorder_activity_troubleshooting_path): [
            "`runtime-observation.json`의 `vitalDBObservation`에 포함",
            "Host watchdog은 기본 60초마다 `runtime-observation.json`을 읽어",
            "guest runtime-state를 current source로 명시",
            "Recorder packet activity의 durable SoT는 SQLite",
            "-> guest runtime-state transfer",
            "-> host observability projection",
            "-> SQLite vitaldb_recorder_activity_buckets",
        ],
    }
    required = {
        relative(packaging_path): [
            "-> Guest Control VitalDB writer",
            "-> Postgres read model",
            "-> Guest Control API /runtime/vitaldb/*",
        ],
        relative(observability_path): [
            "-> Guest/Postgres VitalDB read model",
            "-> Guest Control API /runtime/vitaldb/*",
            "Guest Control API VitalDB read model read state",
            "Guest/Postgres에 저장된 snapshot row는 relationship projection을 재생성하는 canonical evidence",
        ],
        relative(recorder_activity_troubleshooting_path): [
            "Guest/Postgres read model의 1-minute bucket projection",
            "-> Guest/Postgres read model writer",
            "-> Postgres vitaldb observation/activity projection",
            "-> Guest Control API /runtime/vitaldb/*",
            "Guest/Postgres read model을 current source로 명시",
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


def check_redis_relay_status_docs_use_guest_control_api_flow() -> CheckResult:
    observability_path = ROOT / "docs/runtime/macos/observability.md"
    guest_control_api_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    guest_control_usecases_path = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    control_store_path = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/sqlite_control/repository.py"
    )
    redis_relay_loop_path = (
        ROOT / "apps/vitalserver-redis-relay/vitalserver_redis_relay/relay_loop.py"
    )
    redis_relay_status_path = (
        ROOT / "apps/vitalserver-redis-relay/vitalserver_redis_relay/status.py"
    )
    redis_relay_owner_path = (
        ROOT / "apps/vitalserver-redis-relay/vitalserver_redis_relay/status_owner.py"
    )
    redis_relay_main_path = (
        ROOT / "apps/vitalserver-redis-relay/vitalserver_redis_relay/__main__.py"
    )
    redis_relay_readme_path = ROOT / "apps/vitalserver-redis-relay/README.md"
    redis_relay_status_tests_path = ROOT / "apps/vitalserver-redis-relay/tests/test_status.py"
    redis_relay_loop_tests_path = ROOT / "apps/vitalserver-redis-relay/tests/test_relay_loop.py"
    compose_path = MACOS_RUNTIME / "Support/Guest/compose.yaml"
    linux_runtime_controller_service_path = (
        ROOT
        / "apps/vitalserver-platform-agent/packaging/linux"
        / "vitalserver-runtime-controller.service"
    )
    linux_runtime_environment_path = (
        ROOT / "apps/vitalserver-platform-agent/packaging/linux/runtime.env"
    )
    texts = {
        relative(observability_path): read(observability_path),
        relative(guest_control_api_path): read(guest_control_api_path),
        relative(guest_control_usecases_path): read(guest_control_usecases_path),
        relative(control_store_path): read(control_store_path),
        relative(redis_relay_loop_path): read(redis_relay_loop_path),
        relative(redis_relay_status_path): read(redis_relay_status_path),
        relative(redis_relay_owner_path): read(redis_relay_owner_path),
        relative(redis_relay_main_path): read(redis_relay_main_path),
        relative(redis_relay_readme_path): read(redis_relay_readme_path),
        relative(redis_relay_status_tests_path): read(redis_relay_status_tests_path),
        relative(redis_relay_loop_tests_path): read(redis_relay_loop_tests_path),
        relative(compose_path): read(compose_path),
        relative(linux_runtime_controller_service_path): read(
            linux_runtime_controller_service_path
        ),
        relative(linux_runtime_environment_path): read(
            linux_runtime_environment_path
        ),
    }
    forbidden = [
        "Helper status, operator diagnostics",
        "Host/Helper 제품 상태는 이 파일을 직접 읽습니다",
        "RuntimeStatus는 redis-relay-status.json",
        "RedisRelayStatusFileAdapter",
        "TIROSH_REDIS_RELAY_STATUS_PATH",
        "Migration gap: Redis Relay status is still a Guest-side file adapter",
        "json.load(open(path))",
        "Docker health checks use this status file",
        "write_status(",
        "write_unavailable_status(",
        '"scope": "unknown"',
        "Redis relay status owner URL is not configured.",
    ]
    required = [
        (relative(observability_path), "`PUT /runtime/redis-relay/status` owner mutation"),
        (relative(observability_path), "Guest/SQLite owner snapshot"),
        (relative(observability_path), "Host `RuntimeStatus`는 Redis Relay 상태를 조립하지 않습니다."),
        (relative(guest_control_api_path), 'parts == ["runtime", "redis-relay", "status"]'),
        (relative(guest_control_api_path), "usecases.put_redis_relay_status"),
        (relative(guest_control_api_path), "redis_relay=operations"),
        (relative(guest_control_usecases_path), "def put_redis_relay_status"),
        (relative(control_store_path), "RedisRelayStatusRecord"),
        (relative(control_store_path), "def save_status"),
        (relative(control_store_path), "def status"),
        (relative(redis_relay_loop_path), "GuestControlStatusOwnerPublisher"),
        (relative(redis_relay_loop_path), "_record_status("),
        (relative(redis_relay_loop_path), "write_status_artifact(status_path, document)"),
        (relative(redis_relay_status_path), "def build_status_document("),
        (relative(redis_relay_status_path), "def build_unavailable_status_document("),
        (relative(redis_relay_status_path), "def write_status_artifact("),
        (relative(redis_relay_status_path), '"scope": None'),
        (relative(redis_relay_owner_path), "class StatusOwnerConfigurationError"),
        (relative(redis_relay_owner_path), "Exactly one Redis relay status owner URL or socket path is required."),
        (relative(redis_relay_owner_path), "class _UnixSocketHTTPConnection"),
        (relative(redis_relay_owner_path), "REDIS_RELAY_STATUS_OWNER_PATH"),
        (relative(redis_relay_owner_path), 'method="PUT"'),
        (relative(redis_relay_main_path), "--status-owner-socket"),
        (relative(redis_relay_main_path), "exactly one status owner transport is required"),
        (relative(guest_control_api_path), "create_redis_relay_status_owner_server"),
        (relative(guest_control_api_path), "REDIS_RELAY_STATUS_OWNER_PATH"),
        (relative(redis_relay_status_tests_path), "build_status_document("),
        (relative(redis_relay_status_tests_path), "write_status_artifact("),
        (relative(redis_relay_status_tests_path), 'assert document["scope"] is None'),
        (
            relative(redis_relay_loop_tests_path),
            "test_record_status_publishes_owner_when_artifact_write_fails",
        ),
        (relative(redis_relay_readme_path), "`PUT /runtime/redis-relay/status` owner mutation"),
        (relative(redis_relay_readme_path), "they do not read the diagnostics status file as product liveness"),
        (relative(compose_path), "REDIS_RELAY_STATUS_OWNER_URL"),
        (relative(compose_path), "REDIS_RELAY_STATUS_OWNER_SOCKET"),
        (relative(compose_path), "host.docker.internal:host-gateway"),
        (relative(compose_path), "VITALSERVER_RUNTIME_RUN_DIR"),
        (relative(compose_path), "os.path.exists(socket)"),
        (
            relative(linux_runtime_controller_service_path),
            "--redis-relay-status-owner-socket /var/lib/vitalserver/run/redis-relay-status-owner.sock",
        ),
        (
            relative(linux_runtime_environment_path),
            "REDIS_RELAY_STATUS_OWNER_SOCKET=/run/tirosh/status-owner/redis-relay-status-owner.sock",
        ),
        (relative(linux_runtime_environment_path), "REDIS_RELAY_STATUS_OWNER_URL="),
    ]
    matches = [
        f"{path}:{token}"
        for path, text in texts.items()
        for token in forbidden
        if token in text
    ]
    missing = [
        f"{path}:{token}"
        for path, token in required
        if token not in texts[path]
    ]
    deleted_paths = [
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/redis_relay/status_file.py",
        GUEST_TOOLS / "src/tirosh_guest_tools/adapters/outbound/redis_relay/__init__.py",
    ]
    existing_deleted_paths = [relative(path) for path in deleted_paths if path.exists()]
    if matches or missing:
        return CheckResult(
            "redis-relay-status-docs-guest-control-api-flow",
            False,
            f"matches={matches} missing={missing} deleted_paths_present={existing_deleted_paths}",
        )
    if existing_deleted_paths:
        return CheckResult(
            "redis-relay-status-docs-guest-control-api-flow",
            False,
            f"deleted_paths_present={existing_deleted_paths}",
        )
    return CheckResult(
        "redis-relay-status-docs-guest-control-api-flow",
        True,
        "Redis Relay status is published through Guest Control owner mutation "
        "and read from Guest/SQLite snapshot; file remains diagnostics only",
    )


def check_native_control_panel_redis_relay_settings_are_runtime_owned() -> CheckResult:
    environment_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Environment"
        / "RuntimeActionEnvironment.swift"
    )
    errors_path = MACOS_RUNTIME / "Sources/Adapters/Outbound/Errors.swift"
    worker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Commands"
        / "MacRuntimeControlCommandWorker.swift"
    )
    view_model_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels"
        / "RuntimeViewModel.swift"
    )
    texts = {
        relative(path): read(path)
        for path in (environment_path, errors_path, worker_path, view_model_path)
    }
    forbidden = (
        "writeRedisRelaySettingsFile",
        "redisRelaySettingsFileID",
        "redisRelaySettingsFileCreateFailed",
        "tirosh-vitalserver-redis-relay-settings-",
    )
    matches = [
        f"{path}:{token}"
        for path, value in texts.items()
        for token in forbidden
        if token in value
    ]
    required = [
        (relative(worker_path), "try gateway.applyRedisRelaySettings(settings)"),
        (relative(view_model_path), "controlClient.applyRuntimeRedisRelaySettings("),
    ]
    missing = [
        f"{path}:{token}"
        for path, token in required
        if token not in texts[path]
    ]
    if matches or missing:
        return CheckResult(
            "native-control-panel-redis-relay-settings-runtime-owned",
            False,
            f"matches={matches} missing={missing}",
        )
    return CheckResult(
        "native-control-panel-redis-relay-settings-runtime-owned",
        True,
        "The native control panel applies Redis Relay settings only through "
        "the Runtime Controller owner API and has no temporary Host writer",
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


def check_runtime_command_result_preserves_explicit_execution_evidence() -> CheckResult:
    swift_read_models = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlReadModels.swift"
    )
    swift_contract_tests = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    pwa_schema = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    pwa_schema_tests = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts"
    )
    pwa_generated = (
        PWA
        / "src/domain/runtime-control/contracts/generated/runtime-control.ts"
    )
    openapi = ROOT / "docs/runtime/runtime-control.openapi.json"
    texts = {
        relative(swift_read_models): read(swift_read_models),
        relative(swift_contract_tests): read(swift_contract_tests),
        relative(pwa_schema): read(pwa_schema),
        relative(pwa_schema_tests): read(pwa_schema_tests),
        relative(pwa_generated): read(pwa_generated),
        relative(openapi): read(openapi),
    }
    required = {
        relative(swift_read_models): [
            "outputIssues = try container.decode([RuntimeCommandOutputIssue].self, forKey: .outputIssues)",
            "executionIssue = try container.decodeRequiredNullable(",
            "try container.encode(outputIssues, forKey: .outputIssues)",
            "try container.encodeNil(forKey: .executionIssue)",
        ],
        relative(swift_contract_tests): [
            "testRuntimeCommandResultPreservesOutputIssuesAndRequiresCompletePayload",
        ],
        relative(pwa_schema): [
            "outputIssues: z.array(",
            "executionIssue: z",
            ".nullable()",
        ],
        relative(pwa_schema_tests): [
            "outputIssues: []",
            "executionIssue: null",
        ],
        relative(pwa_generated): [
            "outputIssues: components[\"schemas\"][\"RuntimeCommandOutputIssue\"][];",
            "executionIssue: components[\"schemas\"][\"RuntimeProcessExecutionIssue\"] | null;",
        ],
        relative(openapi): [
            "\"RuntimeCommandOutputIssue\"",
            "\"RuntimeProcessExecutionIssue\"",
            "\"outputIssues\"",
            "\"executionIssue\"",
        ],
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = {
        relative(swift_read_models): [
            "outputIssues = try container.decodeIfPresent([RuntimeCommandOutputIssue].self, forKey: .outputIssues) ?? []",
            "executionIssue = try container.decodeIfPresent(RuntimeProcessExecutionIssue.self, forKey: .executionIssue)",
        ],
        relative(swift_contract_tests): [
            "testRuntimeCommandResultPreservesOutputIssuesAndDecodesLegacyPayload",
        ],
        relative(pwa_generated): [
            "result?: components[\"schemas\"][\"RuntimeCommandResult\"];",
            "outputIssues?:",
            "executionIssue?:",
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
            "runtime-command-result-explicit-execution-evidence",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "runtime-command-result-explicit-execution-evidence",
        True,
        "RuntimeCommandResult preserves output decode issues and process execution issues across Swift, OpenAPI, and PWA contracts",
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


def check_vitaldb_observation_snapshot_preserves_explicit_read_state_contract() -> CheckResult:
    swift_read_models = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlReadModels.swift"
    )
    swift_contract_tests = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    pwa_schema = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    read_models_text = read(swift_read_models)
    tests_text = read(swift_contract_tests)
    schema_text = read(pwa_schema)

    required = {
        relative(swift_read_models): [
            "self.observation = try container.decodeRequiredNullable(",
            "VitalDBObservationDocument.self,",
            "self.readError = try container.decodeRequiredNullable(String.self, forKey: .readError)",
            "loaded VitalDB observation snapshots must include observation",
            "failed VitalDB observation snapshots must include readError",
        ],
        relative(swift_contract_tests): [
            "testVitalDBObservationSnapshotRequiresExplicitNullableFieldsAndValidReadState",
        ],
        relative(pwa_schema): [
            "observation: vitalDBObservationSchema.nullable()",
            "readError: requiredNullableString",
            "loaded VitalDB observation snapshots must include observation",
            "failed VitalDB observation snapshots must include readError",
        ],
    }
    texts = {
        relative(swift_read_models): read_models_text,
        relative(swift_contract_tests): tests_text,
        relative(pwa_schema): schema_text,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = [
        "self.observation = try container.decodeIfPresent(VitalDBObservationDocument.self, forKey: .observation)",
        "self.readError = try container.decodeIfPresent(String.self, forKey: .readError)",
    ]
    present = [
        f"{relative(swift_read_models)}:{token}"
        for token in forbidden
        if token in read_models_text
    ]
    if missing or present:
        return CheckResult(
            "vitaldb-observation-snapshot-explicit-read-state-contract",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "vitaldb-observation-snapshot-explicit-read-state-contract",
        True,
        "RuntimeVitalDBObservationSnapshot requires explicit nullable fields and read-state invariants",
    )


def check_vitaldb_relationship_history_preserves_explicit_read_state_contract() -> CheckResult:
    swift_contract = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeVitalRelationshipContracts.swift"
    )
    swift_contract_tests = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    pwa_schema = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    pwa_schema_tests = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts"
    )
    texts = {
        relative(swift_contract): read(swift_contract),
        relative(swift_contract_tests): read(swift_contract_tests),
        relative(pwa_schema): read(pwa_schema),
        relative(pwa_schema_tests): read(pwa_schema_tests),
    }
    required = {
        relative(swift_contract): [
            "state = try container.decode(RuntimeVitalRelationshipHistoryState.self, forKey: .state)",
            "assignments = try container.decode([RuntimeVitalBedAssignmentRecord].self, forKey: .assignments)",
            "events = try container.decode([RuntimeVitalRelationshipEventRecord].self, forKey: .events)",
            "readError = try container.decodeRequiredNullable(String.self, forKey: .readError)",
            "partially loaded VitalDB relationship history must include readError",
            "failed VitalDB relationship history must include readError",
        ],
        relative(swift_contract_tests): [
            "testVitalRelationshipHistoryPreservesExplicitPartialStateAndRequiresCompletePayload",
        ],
        relative(pwa_schema): [
            "partially loaded VitalDB relationship history must include readError",
            "failed VitalDB relationship history must include readError",
        ],
        relative(pwa_schema_tests): [
            'state: "partiallyLoaded"',
            'state: "readFailed"',
        ],
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = {
        relative(swift_contract): [
            "assignments = try container.decodeIfPresent([RuntimeVitalBedAssignmentRecord].self, forKey: .assignments) ?? []",
            "events = try container.decodeIfPresent([RuntimeVitalRelationshipEventRecord].self, forKey: .events) ?? []",
            "state = try container.decodeIfPresent(RuntimeVitalRelationshipHistoryState.self, forKey: .state)",
        ],
        relative(swift_contract_tests): [
            "testVitalRelationshipHistoryPreservesExplicitPartialStateAndDecodesLegacyPayload",
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
            "vitaldb-relationship-history-explicit-read-state-contract",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "vitaldb-relationship-history-explicit-read-state-contract",
        True,
        "RuntimeVitalRelationshipHistory requires explicit arrays, state, nullable readError, and failure invariants",
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
    event_history_reader_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeEventHistoryOwnerReader.swift"
    )
    current_observation_provider_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeVitalDBCurrentObservationProvider.swift"
    )
    observability_paths_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Environment"
        / "RuntimeObservabilityPaths.swift"
    )
    product_reader = read(product_reader_path)
    diagnostics_reader = read(diagnostics_reader_path)
    event_history_reader = read(event_history_reader_path)
    current_observation_provider = read(current_observation_provider_path)
    observability_paths = read(observability_paths_path)
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
    current_observation_required = [
        "guestControlGateway(baseURL).latestVitalDBObservation()",
        "source: .guestControlAPI",
        "guestControl=baseURLUnavailable",
    ]
    observability_paths_required = [
        "InstalledRuntimePaths.defaultInstalled.runtimeEvents.path",
        "InstalledRuntimePaths.defaultInstalled.runtimeObservabilityDB.path",
    ]
    product_reader_required = [
        "guestVitalDBReadModelProvider: .live()",
        "guestVitalDBBedReadModelProvider: .live()",
        "guestVitalDBActivityProvider: .live()",
        "guestVitalDBRelationshipProvider: .live()",
        "Guest VitalDB bed read model is unavailable.",
        "Guest VitalDB activity read model is unavailable.",
        "Guest VitalDB relationship read model is unavailable.",
    ]
    event_required = [
        "CompositeRuntimeEventRepository(",
        "JSONLRuntimeEventRepository(",
        "SQLiteRuntimeEventRepository(",
        "RuntimeObservabilityPaths",
        "paths.runtimeEvents",
        "paths.runtimeObservabilityDB",
    ]
    reader_forbidden = [
        "RuntimeVitalDBHostDiagnosticsProjectionReader",
        "RuntimeVitalDBProjectionReadCollector(",
        "SQLiteVitalDBObservationRepository(url:",
        "JSONLRuntimeEventRepository(",
        "SQLiteRuntimeEventRepository(",
        "CompositeRuntimeEventRepository(",
        "paths.runtimeEvents",
        "paths.runtimeObservabilityDB",
        "hostProjectionReadMode:",
        "makeVitalDBProjectionRepository:",
        "guard hostProjectionReadMode == .diagnostics else",
        "currentObservationProvider: .live(fileStore:",
    ]
    event_forbidden = ["RuntimePaths"]
    diagnostics_forbidden = ["RuntimePaths"]
    observability_paths_forbidden = [
        "RuntimeControlClientConstants.Paths.runtimeEvents",
        "RuntimeControlClientConstants.Paths.runtimeObservabilityDB",
    ]
    current_observation_forbidden = [
        "fileStore",
        "RuntimeFileStore",
        "RuntimeFileReading",
        "RuntimeFileWriting",
        "runtime-observation.json",
        "runtime-status.json",
        "SQLiteVitalDBObservationRepository",
    ]
    forbidden = [
        "fallback projection only when Guest current observation is unavailable",
        "Guest current observation is unavailable",
    ]
    missing = [token for token in required if token not in diagnostics_reader]
    missing += [
        f"{relative(event_history_reader_path)}:{token}"
        for token in event_required
        if token not in event_history_reader
    ]
    missing += [
        f"{relative(current_observation_provider_path)}:{token}"
        for token in current_observation_required
        if token not in current_observation_provider
    ]
    missing += [
        f"{relative(observability_paths_path)}:{token}"
        for token in observability_paths_required
        if token not in observability_paths
    ]
    missing += [
        f"{relative(product_reader_path)}:{token}"
        for token in product_reader_required
        if token not in product_reader
    ]
    present = [
        token
        for token in forbidden
        if token in product_reader or token in diagnostics_reader
    ]
    reader_present = [token for token in reader_forbidden if token in product_reader]
    owner_present = [
        f"{relative(event_history_reader_path)}:{token}"
        for token in event_forbidden
        if token in event_history_reader
    ] + [
        f"{relative(diagnostics_reader_path)}:{token}"
        for token in diagnostics_forbidden
        if token in diagnostics_reader
    ] + [
        f"{relative(observability_paths_path)}:{token}"
        for token in observability_paths_forbidden
        if token in observability_paths
    ] + [
        f"{relative(current_observation_provider_path)}:{token}"
        for token in current_observation_forbidden
        if token in current_observation_provider
    ]
    if missing or present or reader_present or owner_present:
        return CheckResult(
            "vitaldb-host-sqlite-explicit-diagnostics-only",
            False,
            (
                f"missing={missing} forbidden_present={present} "
                f"reader_forbidden={reader_present} owner_forbidden={owner_present}"
            ),
        )
    return CheckResult(
        "vitaldb-host-sqlite-explicit-diagnostics-only",
        True,
        "Host SQLite VitalDB projection reads require explicit diagnostics mode",
    )


def check_runtime_event_sqlite_index_failure_does_not_fail_primary_append() -> CheckResult:
    repository_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Persistence"
        / "CompositeRuntimeEventRepository.swift"
    )
    tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests"
        / "SQLiteRuntimeObservabilityStoreTests.swift"
    )
    repository = read(repository_path)
    tests = read(tests_path)
    required = [
        (relative(repository_path), "try primary.append(event)", repository),
        (relative(repository_path), "try secondary.append(event)", repository),
        (relative(repository_path), "CompositeRuntimeEventRepositoryError.secondaryAppendFailed", repository),
        (relative(repository_path), '"sqlite=\\(secondaryReadError)"', repository),
        (relative(repository_path), '"jsonl=\\($0)"', repository),
        (
            relative(tests_path),
            "testCompositeRepositoryLogsSecondaryAppendFailureWithoutFailingPrimaryAppend",
            tests,
        ),
        (relative(tests_path), "try repository.append(event(id: \"event-1\"", tests),
        (relative(tests_path), "XCTAssertEqual(page.state, .partiallyLoaded)", tests),
        (relative(tests_path), 'page.readError?.contains("sqlite=")', tests),
    ]
    forbidden = [
        (relative(repository_path), "throw appendError", repository),
        (relative(repository_path), "let appendError =", repository),
        (
            relative(repository_path),
            "throw CompositeRuntimeEventRepositoryError.secondaryAppendFailed",
            repository,
        ),
        (relative(repository_path), "readError: [secondaryReadError, primaryPage.readError]", repository),
        (
            relative(tests_path),
            "XCTAssertThrowsError(\n            try repository.append(event(id: \"event-1\"",
            tests,
        ),
    ]
    missing = [
        f"{path}:{token}"
        for path, token, text in required
        if token not in text
    ]
    present = [
        f"{path}:{token}"
        for path, token, text in forbidden
        if token in text
    ]
    if missing or present:
        return CheckResult(
            "runtime-event-sqlite-index-failure-no-primary-append-failure",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "runtime-event-sqlite-index-failure-no-primary-append-failure",
        True,
        "Runtime event SQLite index append failures stay diagnostics and do not fail the primary event append",
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


def check_current_health_has_no_reported_vm_error_input(
) -> CheckResult:
    usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeHealth"
        / "EvaluateRuntimeHealthUseCase.swift"
    )
    evaluator_path = (
        MACOS_RUNTIME / "Sources/Domain/Policies/RuntimeHealthEvaluator.swift"
    )
    policy_path = (
        MACOS_RUNTIME / "Sources/Domain/Policies/RuntimeVMHealthPolicy.swift"
    )
    lifecycle_document_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeVMLifecycleDocument.swift"
    )
    vm_error_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeVMError.swift"
    )
    failure_reason_path = (
        MACOS_RUNTIME / "Sources/Contracts/Shared/RuntimeFailureReason.swift"
    )
    tests_path = (
        MACOS_RUNTIME
        / "Tests/DomainTests/Policies/RuntimeHealthEvaluatorTests.swift"
    )
    contract_tests_path = (
        MACOS_RUNTIME / "Tests/ContractsTests/ContractsTests.swift"
    )
    usecase_text = read(usecase_path)
    evaluator_text = read(evaluator_path)
    policy_text = read(policy_path)
    lifecycle_document_text = read(lifecycle_document_path)
    vm_error_text = read(vm_error_path)
    failure_reason_text = read(failure_reason_path)
    reported_vm_errors_text = text_between(
        lifecycle_document_text,
        "var reportedVMErrors: [RuntimeVMError]",
        "\n}\n",
    )
    tests_text = read(tests_path)
    contract_tests_text = read(contract_tests_path)
    required = {
        relative(lifecycle_document_path): [
            "var reportedVMErrors: [RuntimeVMError]",
            "case .diskAttachmentInvalid:",
            "case .guestFilesystemReadOnly:",
            "case .guestDiskIO:",
            "case .guestKernelPanic:",
        ],
        relative(tests_path): [
            "testVMLifecycleTerminalReasonReportsStoragePreservingVMError",
            "RuntimeVMLifecycleDocument(",
            "terminalReason:",
        ],
    }
    forbidden = {
        relative(usecase_path): [
            "reportedVMErrors",
        ],
        relative(evaluator_path): [
            "reportedVMErrors",
        ],
        relative(policy_path): [
            "input.reportedVMErrors",
            "currentHealthVMErrors",
        ],
        f"{relative(lifecycle_document_path)}:reportedVMErrors": [
            "runtimeObservation",
            "BootstrapResult",
            "guestBootstrap",
            ".runtimeStateMissing",
            ".runtimeStateInvalid",
            ".runtimeStateStale",
            ".guestBootstrapResultMissing",
            ".guestBootstrapResultUnavailable",
        ],
        relative(vm_error_path): [
            "case runtimeStateMissing",
            "case runtimeStateInvalid",
            "case runtimeStateStale",
            "case guestBootstrapResultMissing",
            "case guestBootstrapResultUnavailable",
            'case "vm-runtime-state-missing"',
            'case "vm-runtime-state-invalid"',
            'case "vm-runtime-state-stale"',
            'case "vm-guest-bootstrap-result-missing"',
            'case "vm-guest-bootstrap-result-unavailable"',
        ],
        relative(failure_reason_path): [
            "case guestRuntimeStateStale",
            "case guestRuntimeStateMissing",
            "case guestRuntimeStateInvalid",
            "case guestRuntimeStateLoadFailed",
            "case guestRuntimeStateMetadataReadFailed",
            "case guestBootstrapResultMissing",
            "case guestBootstrapResultUnavailable",
            'case "guest-bootstrap-result-missing"',
            'case "guest-bootstrap-result-unavailable"',
            'case "vm-runtime-state-missing"',
            'case "guest-runtime-state-stale"',
            'case "guest-runtime-state-invalid"',
            'hasPrefix("guest-runtime-state-load-failed-")',
            'hasPrefix("guest-runtime-state-metadata-read-failed-")',
        ],
        relative(contract_tests_path): [
            "vm-runtime-state-missing",
            "vm-runtime-state-invalid",
            "vm-runtime-state-stale",
            "vm-guest-bootstrap-result-missing",
            "vm-guest-bootstrap-result-unavailable",
            "guest-bootstrap-result-missing",
            "guest-bootstrap-result-unavailable",
            "guest-runtime-state-load-failed",
            "guest-runtime-state-metadata-read-failed",
            "runtime-status-document-missing",
            "runtime-status-document-stale",
            "runtime-status-document-invalid",
            "container-observation-missing",
            "container-observation-read-failed",
            "vitaldb-observation-missing",
            "vitaldb-observation-read-failed",
        ],
    }
    texts = {
        relative(usecase_path): usecase_text,
        relative(evaluator_path): evaluator_text,
        relative(policy_path): policy_text,
        relative(lifecycle_document_path): lifecycle_document_text,
        relative(vm_error_path): vm_error_text,
        relative(failure_reason_path): failure_reason_text,
        f"{relative(lifecycle_document_path)}:reportedVMErrors": reported_vm_errors_text,
        relative(tests_path): tests_text,
        relative(contract_tests_path): contract_tests_text,
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    present = {
        path: [token for token in tokens if token in texts[path]]
        for path, tokens in forbidden.items()
        if any(token in texts[path] for token in tokens)
    }
    if missing or present:
        return CheckResult(
            "current-health-no-reported-vm-error-input",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "current-health-no-reported-vm-error-input",
        True,
        "Current health evaluation has no arbitrary reported VM error input; "
        "VM terminal errors come from the explicit VM lifecycle document",
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
        (
            "apps/vitalserver-macos-runtime/Sources/Domain/Policies/"
            "RuntimeHealthSnapshotPolicy.swift"
        ): read(
            MACOS_RUNTIME
            / "Sources/Domain/Policies/RuntimeHealthSnapshotPolicy.swift"
        ),
        (
            "apps/vitalserver-macos-runtime/Sources/Domain/Policies/"
            "RuntimeWatchdogRecoveryPolicy.swift"
        ): read(
            MACOS_RUNTIME
            / "Sources/Domain/Policies/RuntimeWatchdogRecoveryPolicy.swift"
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
        "RuntimeGuestBootstrapResultReader",
        "loadBootstrapResultDocument",
        "GuestBootstrapEvaluator",
        "guestBootstrapResult",
        "guestBootstrapAssessment",
        "return .failed(vmIP: nil, message: guestAddressRead.failureStatusText)",
        "return .readFailed(guestAddressRead.failureStatusText)",
        'readError: "guestControl=\\(guestAddressRead.failureStatusText)"',
        "hasGuestAddressFailure",
        "snapshot.guestAddressRead.state",
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
        "diagnostics, runtime-state file metadata, bootstrap-result file state, "
        "or Guest address file read failures as current health failures",
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
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"

    checks = {
        relative(swift_status_path): [
            "public var vitalDBObservation",
            "case vitalDBObservation",
            "guestRuntimeStateError",
            "case operation",
            "case statusMessage",
            "case updatedAt",
            "case startedAt",
            "case progress",
            "case statusDocumentError",
            "case installStateDocument",
            "case installStateDocumentError",
            "public var operation:",
            "public var statusMessage:",
            "public var updatedAt:",
            "public var startedAt:",
            "public var progress:",
            "public var statusDocumentError:",
            "public var installStateDocument:",
            "public var installStateDocumentError:",
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

    swift_assembly = read(swift_assembly_path)
    swift_runtime_status_assembly_block = text_between(
        swift_assembly,
        "return RuntimeStatus(",
        "\n        )",
    )
    for token in [
        "vitalDBObservation: nil",
        "guestRuntimeStateError:",
        "operation: nil",
        "statusMessage: nil",
        "updatedAt: nil",
        "startedAt: nil",
        "progress: nil",
        "statusDocumentError:",
        "installStateDocument:",
        "installStateDocumentError:",
        "RuntimeInstallStateRead",
    ]:
        if token in swift_runtime_status_assembly_block:
            matches.append(f"{relative(swift_assembly_path)}:RuntimeStatus.{token}")

    retired_product_fields = [
        "guestServicesReadState",
        "guestServices",
        "guestServiceStatuses",
        "guestServiceResources",
        "guestServiceResourceReadIssues",
        "guestStackProbeErrors",
        "guestServicesReadError",
        "cpuUsagePercent",
        "memory",
        "vitalServerMemory",
        "recorderIngressMemory",
        "redisMemory",
        "systemDisk",
    ]
    swift_runtime_status_block = read(swift_status_path).split(
        "public struct PlatformState:", 1
    )[-1]
    for field in retired_product_fields:
        if field in swift_runtime_status_block:
            matches.append(f"{relative(swift_status_path)}:RuntimeStatus.{field}")

    pwa_schema = read(pwa_schema_path)
    pwa_status_block = text_between(
        pwa_schema,
        "export const platformStateSchema",
        "const runtimeInstallOperationStateSchema",
    )
    pwa_status_shape_block = text_between(
        pwa_status_block,
        ".object({",
        "  })\n  .passthrough()",
    )
    for token in [
        "vitalDBObservation",
        "guestRuntimeStateError",
        "operation:",
        "statusMessage:",
        "updatedAt:",
        "startedAt:",
        "progress:",
        "statusDocumentError:",
        "installStateDocument:",
        "installStateDocumentError:",
    ]:
        if token in pwa_status_block:
            matches.append(f"{relative(pwa_schema_path)}:runtimeStatusSchema.{token}")
    for field in retired_product_fields:
        if f"{field}:" in pwa_status_shape_block:
            matches.append(f"{relative(pwa_schema_path)}:runtimeStatusSchema.{field}")
        if f'"{field}"' not in pwa_status_block:
            matches.append(
                f"{relative(pwa_schema_path)}:missing retired-field rejection.{field}"
            )

    pwa_generated = read(pwa_generated_path)
    pwa_generated_status_block = text_between(
        pwa_generated,
        "PlatformState: {",
        "RuntimeEventHistory:",
    )
    for token in [
        "vitalDBObservation",
        "guestRuntimeStateError",
        "operation?:",
        "statusMessage?:",
        "updatedAt?:",
        "startedAt?:",
        "progress?:",
        "statusDocumentError?:",
        "installStateDocument?:",
        "installStateDocumentError?:",
    ]:
        if token in pwa_generated_status_block:
            matches.append(f"{relative(pwa_generated_path)}:RuntimeStatus.{token}")
    for field in retired_product_fields:
        if f"{field}?:" in pwa_generated_status_block:
            matches.append(f"{relative(pwa_generated_path)}:RuntimeStatus.{field}")

    openapi = read(openapi_path)
    openapi_status_block = text_between(
        openapi,
        '"PlatformState": {',
        '"RuntimeEventHistory":',
    )
    openapi_status_properties_block = text_between(
        openapi_status_block,
        '"properties": {',
        '"not": {',
    )
    for token in [
        '"vitalDBObservation"',
        '"guestRuntimeStateError"',
        '"operation"',
        '"statusMessage"',
        '"updatedAt"',
        '"startedAt"',
        '"progress"',
        '"statusDocumentError"',
        '"installStateDocument"',
        '"installStateDocumentError"',
    ]:
        if token in openapi_status_block:
            matches.append(f"{relative(openapi_path)}:RuntimeStatus.{token}")
    for field in retired_product_fields:
        if f'"{field}"' in openapi_status_properties_block:
            matches.append(f"{relative(openapi_path)}:RuntimeStatus.{field}")
        if f'"{field}"' not in openapi_status_block:
            matches.append(
                f"{relative(openapi_path)}:missing retired-field rejection.{field}"
            )

    if matches:
        return CheckResult(
            "runtime-status-contract-no-vitaldb-observation",
            False,
            f"matches={matches[:10]}",
        )
    return CheckResult(
        "runtime-status-contract-no-vitaldb-observation",
        True,
        "RuntimeStatus contract does not carry Runtime-owned product state, legacy VitalDB, runtime-state, "
        "operation, progress, message, timestamp, status document diagnostics, "
        "or install-state owner fields",
    )


def check_host_health_uses_guest_control_ready_for_guest_readiness() -> CheckResult:
    health_checker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Health/RuntimeHealthChecker.swift"
    )
    health_checker_composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/RuntimeHealthCheckerComposition.swift"
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
    health_checker_composition = read(health_checker_composition_path)
    gateway = read(gateway_path)
    protocol = read(protocol_path)
    contract = read(contract_path)
    health_usecase = read(health_usecase_path)
    status_reader = read(status_reader_path)
    gateway_tests = read(gateway_tests_path)
    health_tests = read(health_tests_path)
    required = {
        relative(health_checker_path): [
            "guestAddressProvider: any RuntimeGuestAddressProvider",
            "self.guestAddressProvider = guestAddressProvider",
            "guestControlReadiness()",
            "guestControlGateway(baseURL).ready()",
            "readGuestAddress()",
        ],
        relative(health_checker_composition_path): [
            "guestAddressProvider ?? RuntimeControlAPIGuestAddressProvider()",
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
        relative(health_checker_composition_path): health_checker_composition,
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
            "currentHealthGuestRuntimeObservationReadFailures",
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
        relative(health_checker_path): [
            "RuntimeVMIPFileGuestAddressProvider(",
            "context.installedPaths.vmIPFile",
        ],
        relative(health_checker_composition_path): [
            "RuntimeBootstrapGuestAddressProvider.live(",
            "vmIPFile: installedPaths.vmIPFile",
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
        'vm_ip_file="${vm_home}/data/run/vm-ip"',
        'runtime_endpoint_file="${vm_home}/run/runtime-endpoint.json"',
        "read_vm_ip()",
        "upstream_ready()",
        "proxy_ready()",
        "publish_runtime_endpoint()",
        'printf \'{"address":"%s","source":"platform-agent","state":"loaded"}',
        'mv -f "${temporary}" "${runtime_endpoint_file}"',
        "clear_runtime_endpoint()",
        "waiting for Platform runtime endpoint source",
    ]
    forbidden = [
        'state_file="${vm_home}/data/run/runtime-observation.json"',
        "read_state_value()",
        "read_guest_http()",
        "waiting for VM runtime bootstrap",
        "waiting for VM runtime observation",
        'publish_guest_address_owner "${vm_ip}" || true',
        "VITALSERVER_RUNTIME_CONTROL_API_BASE_URL",
        "/platform/runtime-endpoint",
        "load_guest_address_owner()",
        "guestHTTP",
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
        "Host proxy promotes bootstrap address evidence into the durable Platform endpoint owner and uses HTTP readiness probes",
    )


def check_devtools_runtime_wait_uses_bootstrap_address_and_http_probe() -> CheckResult:
    path = (
        ROOT
        / "packages/vitalserver-devtools/src/tirosh_vitalserver/devtools"
        / "adapters/macos_release/runtime_lifecycle.py"
    )
    legacy_runtime_state_path = (
        ROOT
        / "packages/vitalserver-devtools/src/tirosh_vitalserver/devtools"
        / "adapters/macos_release/runtime_state.py"
    )
    text = read(path)
    required = [
        "adapters.macos_release.runtime_paths import",
        "runtime_vm_ip_file(",
        "read_runtime_bootstrap_vm_ip(",
        "probe_guest_runtime_http(",
        "Waiting for VM IP bootstrap file",
        "Waiting for VM HTTP through bootstrap address",
        "VM HTTP ready: upstream=http://",
        "recorder-ingress/health",
    ]
    forbidden = [
        "read_runtime_state_vm_ip",
        "read_runtime_state_guest_http",
        "runtime_state_file",
        "Waiting for runtime-state VM IP",
        "Waiting for runtime-state guestHTTP",
        "VM HTTP ready: guestHTTP",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    if legacy_runtime_state_path.exists():
        present.append(
            f"{relative(legacy_runtime_state_path)}:devtools runtime-state reader helpers must be removed"
        )
    if missing or present:
        return CheckResult(
            "devtools-runtime-wait-bootstrap-address-http-probe",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "devtools-runtime-wait-bootstrap-address-http-probe",
        True,
        "devtools runtime wait reads vm-ip bootstrap address and direct HTTP "
        "probes instead of runtime-state vmIP/guestHTTP",
    )


def check_devtools_runtime_health_uses_bootstrap_address_and_http_probe() -> CheckResult:
    lifecycle_path = (
        ROOT
        / "packages/vitalserver-devtools/src/tirosh_vitalserver/devtools"
        / "adapters/macos_release/runtime_lifecycle.py"
    )
    installed_path = (
        ROOT
        / "packages/vitalserver-devtools/src/tirosh_vitalserver/devtools"
        / "adapters/macos_release/installed_runtime.py"
    )
    texts = {
        relative(lifecycle_path): read(lifecycle_path),
        relative(installed_path): read(installed_path),
    }
    required = [
        (relative(lifecycle_path), "read_runtime_bootstrap_vm_ip(vm_home)"),
        (relative(lifecycle_path), "probe_guest_runtime_http(vm_ip)"),
        (relative(lifecycle_path), "VM IP bootstrap address is unavailable"),
        (relative(installed_path), "read_runtime_bootstrap_vm_ip(vm_home)"),
        (relative(installed_path), "probe_guest_runtime_http(vm_ip)"),
    ]
    forbidden = {
        path: [
            "read_runtime_state(",
            "read_runtime_state_string(",
            "read_runtime_state_vm_ip",
            "read_runtime_state_guest_http",
            "reported guestHTTP",
            "runtime observation guestHTTP",
        ]
        for path in texts
    }
    missing = [
        f"{path}:{token}"
        for path, token in required
        if token not in texts[path]
    ]
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    if missing or present:
        return CheckResult(
            "devtools-runtime-health-bootstrap-address-http-probe",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "devtools-runtime-health-bootstrap-address-http-probe",
        True,
        "devtools runtime health/status reads vm-ip bootstrap address and "
        "direct HTTP probes instead of runtime-state vmIP/guestHTTP",
    )


def check_dev_make_proxy_start_uses_guest_address_owner() -> CheckResult:
    make_path = ROOT / "make/vm/runtime.mk"
    cli_path = (
        ROOT
        / "packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/cli.py"
    )
    lifecycle_path = (
        ROOT
        / "packages/vitalserver-devtools/src/tirosh_vitalserver/devtools"
        / "adapters/macos_release/runtime_lifecycle.py"
    )
    texts = {
        relative(make_path): read(make_path),
        relative(cli_path): read(cli_path),
        relative(lifecycle_path): read(lifecycle_path),
    }
    required = [
        (relative(make_path), "macos-runtime-guest-address-proxy-upstream"),
        (relative(make_path), "VITALSERVER_RUNTIME_CONTROL_API_BASE_URL"),
        (relative(cli_path), "macos-runtime-guest-address-proxy-upstream"),
        (relative(cli_path), "RuntimeGuestAddressOwnerInput"),
        (relative(lifecycle_path), "print_runtime_guest_address_proxy_upstream"),
        (relative(lifecycle_path), "runtime_control_guest_address_request"),
        (relative(lifecycle_path), "/platform/runtime-endpoint"),
        (relative(lifecycle_path), 'method="PUT"'),
        (relative(lifecycle_path), 'method="GET"'),
    ]
    forbidden = {
        relative(make_path): [
            'cat "$(VM_HOME)/data/run/vm-ip"',
            "Set VM_PROXY_UPSTREAM or run make devtools/wait/ip first.",
        ],
        relative(lifecycle_path): [
            "return f\"{bootstrap_address}:80\"",
        ],
    }
    missing = [
        f"{path}:{token}"
        for path, token in required
        if token not in texts[path]
    ]
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    if missing or present:
        return CheckResult(
            "dev-make-proxy-start-guest-address-owner",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "dev-make-proxy-start-guest-address-owner",
        True,
        "dev runtime/proxy/start derives upstream from Runtime Control Guest "
        "address owner instead of reading vm-ip directly",
    )


def check_managed_operation_guard_does_not_read_runtime_state() -> CheckResult:
    path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeManagedOperationGuardComposition.swift"
    )
    text = read(path)
    usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeHealth"
        / "GuardManagedRuntimeOperationUseCase.swift"
    )
    usecase_text = read(usecase_path)
    watchdog_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeHealth"
        / "WatchdogRuntimeUseCase.swift"
    )
    watchdog_text = read(watchdog_path)
    runner_composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeWatchdogRunnerComposition.swift"
    )
    runner_composition_text = read(runner_composition_path)
    runner_workflow_path = (
        MACOS_RUNTIME
        / "Sources/Workflow/RuntimeWatchdog"
        / "RuntimeWatchdogRunner.swift"
    )
    runner_workflow_text = read(runner_workflow_path)
    required = [
        "loadOperationLease",
    ]
    forbidden = [
        "loadRuntimeStateDocument",
        "GuestRuntimeObservationDocument",
        "runtimeState.bootID",
        "runtimeBootID",
        "statusReporter:",
        "loadStatus:",
        "loadStatusResult",
        "RuntimeGuestBootstrapResultReader",
        "loadBootstrapResultDocument",
        "activeGuestBootstrap",
        "RuntimeGuestBootstrapOperation",
    ]
    missing = [token for token in required if token not in text]
    present = [token for token in forbidden if token in text]
    for token in [
        "loadStatus:",
        "RuntimeStatusDocumentLoadResult",
        "RuntimeGuestBootstrapResultReader",
        "loadBootstrapResultDocument",
        "activeGuestBootstrap",
    ]:
        if token in usecase_text:
            present.append(f"{relative(usecase_path)}:{token}")
    for token in [
        "statusManagedOperationGuardPlan",
        "statusReadFailureGuardPlan",
        "RuntimeStatusDocumentLoadResult",
        "guestBootstrapManagedOperationGuardPlan",
    ]:
        if token in watchdog_text:
            present.append(f"{relative(watchdog_path)}:{token}")
    for token in [
        "currentRuntimeStatus",
        "RuntimeStatusDocumentLoadResult",
        "loadStatusResult",
    ]:
        if token in runner_composition_text:
            present.append(f"{relative(runner_composition_path)}:{token}")
        if token in runner_workflow_text:
            present.append(f"{relative(runner_workflow_path)}:{token}")
    if missing or present:
        return CheckResult(
            "managed-operation-guard-no-runtime-state-read",
            False,
            f"missing={missing} forbidden_present={present} path={relative(path)}",
        )
    return CheckResult(
        "managed-operation-guard-no-runtime-state-read",
        True,
        "watchdog managed-operation guard uses operation leases instead of "
        "runtime-state, runtime-status, or bootstrap-result reads",
    )


def check_cli_host_centralizes_operation_lease_owner_adapter_selection(
) -> CheckResult:
    operations_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Lifecycle"
        / "RuntimeLifecycle+OperationsComposition.swift"
    )
    runtime_lifecycle_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeLifecycle.swift"
    )
    bundle_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary/Lifecycle"
        / "RuntimeLifecycle+BundleComposition.swift"
    )
    data_backup_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeDataBackupComposition.swift"
    )
    endpoint_routing_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpointRouting.swift"
    )
    command_routes_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlHTTPCommandRoutes.swift"
    )
    api_handler_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlClientAPIReadHandler.swift"
    )
    mac_api_handler_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent"
        / "MacRuntimeControlAPIHandler.swift"
    )
    mac_local_api_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent"
        / "MacRuntimeControlLocalAPI.swift"
    )
    mac_environment_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent"
        / "MacPlatformAgentService.swift"
    )
    mac_lease_controller_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent"
        / "RuntimeControlOperationLeaseController.swift"
    )
    json_file_operation_lease_repository_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Persistence"
        / "JSONFileRuntimeOperationLeaseRepository.swift"
    )
    mac_runtime_client_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Client"
        / "MacRuntimeControlClient.swift"
    )
    runtime_control_constants_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Environment"
        / "RuntimeControlClientConstants.swift"
    )
    log_export_sources_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Logs"
        / "RuntimeLogExportSources.swift"
    )
    log_export_contract_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl"
        / "RuntimeLogExportSourceContracts.swift"
    )
    api_owner_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/RuntimeControlAPI"
        / "RuntimeControlAPIOperationLeaseOwner.swift"
    )
    api_owner_tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests"
        / "RuntimeControlAPIOperationLeaseOwnerTests.swift"
    )
    host_client_contract_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl"
        / "RuntimeClientContracts.swift"
    )
    api_tests_path = (
        MACOS_RUNTIME
        / "Tests/InboundAdaptersTests/RuntimeControlAPI"
        / "RuntimeControlAPITests.swift"
    )
    runtime_control_docs_path = ROOT / "docs/runtime/macos/runtime-control-api.md"
    operation_lease_race_troubleshooting_path = (
        ROOT / "docs/troubleshooting/053_update-watchdog-operation-lease-race.md"
    )
    update_shutdown_troubleshooting_path = (
        ROOT / "docs/troubleshooting/061_update-shutdown-service-failed-without-result.md"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    operations_text = read(operations_path)
    runtime_lifecycle_text = read(runtime_lifecycle_path)
    bundle_text = read(bundle_path)
    data_backup_text = read(data_backup_path)
    endpoint_routing_text = read(endpoint_routing_path)
    command_routes_text = read(command_routes_path)
    api_handler_text = read(api_handler_path)
    mac_api_handler_text = read(mac_api_handler_path)
    mac_local_api_text = read(mac_local_api_path)
    mac_environment_text = read(mac_environment_path)
    mac_lease_controller_text = read(mac_lease_controller_path)
    mac_runtime_client_text = read(mac_runtime_client_path)
    runtime_control_constants_text = read(runtime_control_constants_path)
    log_export_sources_text = read(log_export_sources_path)
    log_export_contract_text = read(log_export_contract_path)
    api_owner_text = read(api_owner_path)
    api_owner_tests_text = read(api_owner_tests_path)
    host_client_contract_text = read(host_client_contract_path)
    api_tests_text = read(api_tests_path)
    runtime_control_docs_text = read(runtime_control_docs_path)
    operation_lease_race_troubleshooting_text = read(
        operation_lease_race_troubleshooting_path
    )
    update_shutdown_troubleshooting_text = read(update_shutdown_troubleshooting_path)
    openapi_text = read(openapi_path)
    required = [
        (
            relative(operations_path),
            "func runtimeOperationLeaseOwner() -> any RuntimeOperationLeaseOwner",
            operations_text,
        ),
        (
            relative(operations_path),
            "runtimeOperationLeaseOwnerFactory()",
            operations_text,
        ),
        (
            relative(runtime_lifecycle_path),
            "JSONFileRuntimeOperationLeaseRepository(url: container.installedPaths.runtimeOperationLease)",
            runtime_lifecycle_text,
        ),
        (
            relative(api_owner_path),
            'path: "/platform/operations"',
            api_owner_text,
        ),
        (
            relative(api_owner_path),
            'path: "/platform/operations/lease/acquire"',
            api_owner_text,
        ),
        (
            relative(api_owner_path),
            'path: "/platform/operations/lease/heartbeat"',
            api_owner_text,
        ),
        (
            relative(api_owner_path),
            'path: "/platform/operations/lease/release"',
            api_owner_text,
        ),
        (
            relative(api_owner_tests_path),
            "testAcquireHeartbeatAndReleasePostOwnerMutationRoutes",
            api_owner_tests_text,
        ),
        (
            relative(api_owner_tests_path),
            "testHTTPFailureDoesNotBecomeMissingLease",
            api_owner_tests_text,
        ),
        (
            relative(bundle_path),
            "runtimeOperationLeaseOwner().acquire",
            bundle_text,
        ),
        (
            relative(bundle_path),
            "runtimeOperationLeaseOwner().heartbeat",
            bundle_text,
        ),
        (
            relative(bundle_path),
            "runtimeOperationLeaseOwner().release",
            bundle_text,
        ),
        (
            relative(data_backup_path),
            "lifecycle.runtimeOperationLeaseOwner()",
            data_backup_text,
        ),
        (
            relative(endpoint_routing_path),
            'path: "/platform/operations/lease/acquire", scope: .platformAffordance',
            endpoint_routing_text,
        ),
        (
            relative(endpoint_routing_path),
            'path: "/platform/operations/lease/heartbeat", scope: .platformAffordance',
            endpoint_routing_text,
        ),
        (
            relative(endpoint_routing_path),
            'path: "/platform/operations/lease/release", scope: .platformAffordance',
            endpoint_routing_text,
        ),
        (
            relative(command_routes_path),
            "handler.acquireOperationLease(acquireRequest)",
            command_routes_text,
        ),
        (
            relative(command_routes_path),
            "handler.heartbeatOperationLease(heartbeatRequest)",
            command_routes_text,
        ),
        (
            relative(command_routes_path),
            "handler.releaseOperationLease(releaseRequest)",
            command_routes_text,
        ),
        (
            relative(api_handler_path),
            "hostClient.acquireOperationLease(request.document)",
            api_handler_text,
        ),
        (
            relative(api_handler_path),
            "hostClient.heartbeatOperationLease(",
            api_handler_text,
        ),
        (
            relative(api_handler_path),
            "hostClient.releaseOperationLease(operationId: request.operationId)",
            api_handler_text,
        ),
        (
            relative(mac_api_handler_path),
            "operationLeaseClient.acquireOperationLease(request.document)",
            mac_api_handler_text,
        ),
        (
            relative(mac_api_handler_path),
            "operationLeaseClient.heartbeatOperationLease(",
            mac_api_handler_text,
        ),
        (
            relative(mac_api_handler_path),
            "operationLeaseClient.releaseOperationLease(operationId: request.operationId)",
            mac_api_handler_text,
        ),
        (
            relative(mac_api_handler_path),
            "protocol RuntimeOperationLeaseMutationClient",
            mac_api_handler_text,
        ),
        (
            relative(mac_environment_path),
            "RuntimeControlOperationLeaseController(",
            mac_environment_text,
        ),
        (
            relative(mac_environment_path),
            "let operationLeaseOwner = JSONFileRuntimeOperationLeaseRepository(",
            mac_environment_text,
        ),
        (
            relative(mac_environment_path),
            "url: installedPaths.runtimeOperationLease",
            mac_environment_text,
        ),
        (
            relative(mac_environment_path),
            "operationLeaseReader: operationLeaseController",
            mac_environment_text,
        ),
        (
            relative(mac_environment_path),
            "operationLeaseClient: operationLeaseController",
            mac_environment_text,
        ),
        (
            relative(mac_lease_controller_path),
            "final class RuntimeControlOperationLeaseController",
            mac_lease_controller_text,
        ),
        (
            relative(mac_lease_controller_path),
            "RuntimeOperationLeaseOwner",
            mac_lease_controller_text,
        ),
        (
            relative(mac_lease_controller_path),
            "RuntimeOperationLeaseMutationClient",
            mac_lease_controller_text,
        ),
        (
            relative(host_client_contract_path),
            "func acquireOperationLease(_ document: RuntimeOperationLeaseDocument)",
            host_client_contract_text,
        ),
        (
            relative(api_tests_path),
            'path: "/platform/operations/lease/acquire"',
            api_tests_text,
        ),
        (
            relative(api_tests_path),
            "testRuntimeControlClientReadHandlerAdaptsPlatformAffordances",
            api_tests_text,
        ),
        (
            relative(runtime_control_docs_path),
            "Platform operation lease mutation은 Platform affordance API",
            runtime_control_docs_text,
        ),
        (
            relative(operation_lease_race_troubleshooting_path),
            "Current operation 표시는 Runtime Control operation-state API와 durable Platform operation lease owner에서 오고",
            operation_lease_race_troubleshooting_text,
        ),
        (
            relative(operation_lease_race_troubleshooting_path),
            "`vm/run/runtime-operation-lease.json`은 그 owner document이며 API와 CLI workflow가 같은 lock/atomic-write repository를 공유합니다.",
            operation_lease_race_troubleshooting_text,
        ),
        (
            relative(update_shutdown_troubleshooting_path),
            "/platform/operations",
            update_shutdown_troubleshooting_text,
        ),
        (
            relative(update_shutdown_troubleshooting_path),
            "Runtime Control operation-state에 active operation lease와 `expiresAt`이 있는지",
            update_shutdown_troubleshooting_text,
        ),
        (
            relative(openapi_path),
            '"/platform/operations/lease/acquire"',
            openapi_text,
        ),
        (
            relative(openapi_path),
            '"/platform/operations/lease/heartbeat"',
            openapi_text,
        ),
        (
            relative(openapi_path),
            '"/platform/operations/lease/release"',
            openapi_text,
        ),
        (
            relative(openapi_path),
            '"RuntimeOperationLeaseMutationResponse"',
            openapi_text,
        ),
        (
            relative(log_export_contract_path),
            "diagnostics/platform/\\(RuntimeHostOwnerFileNames.operationLease)",
            log_export_contract_text,
        ),
        (
            relative(log_export_sources_path),
            "return installed.runtimeOperationLease",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "let installed = InstalledRuntimePaths.defaultInstalled",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "return installed.runtimeStatus",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "return installed.runtimeEvents",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "return installed.runtimeObservation",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "return installed.vmLifecycle",
            log_export_sources_text,
        ),
    ]
    missing = [
        f"{path}:{token}"
        for path, token, text in required
        if token not in text
    ]
    if not json_file_operation_lease_repository_path.exists():
        missing.append(
            f"{relative(json_file_operation_lease_repository_path)}:durable Platform operation lease owner is missing"
        )
    forbidden = [
        (
            relative(operations_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            operations_text,
        ),
        (
            relative(operations_path),
            "installedPaths.runtimeOperationLease",
            operations_text,
        ),
        (
            relative(bundle_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            bundle_text,
        ),
        (
            relative(data_backup_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            data_backup_text,
        ),
        (
            relative(bundle_path),
            "installedPaths.runtimeOperationLease",
            bundle_text,
        ),
        (
            relative(data_backup_path),
            "installedPaths.runtimeOperationLease",
            data_backup_text,
        ),
        (
            relative(api_handler_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            api_handler_text,
        ),
        (
            relative(api_handler_path),
            "runtimeOperationLease",
            api_handler_text,
        ),
        (
            relative(mac_api_handler_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            mac_api_handler_text,
        ),
        (
            relative(mac_api_handler_path),
            "runtimeOperationLease",
            mac_api_handler_text,
        ),
        (
            relative(mac_runtime_client_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            mac_runtime_client_text,
        ),
        (
            relative(mac_runtime_client_path),
            "operationLeaseOwner",
            mac_runtime_client_text,
        ),
        (
            relative(runtime_control_constants_path),
            "runtimeOperationLease = installed.runtimeOperationLease.path",
            runtime_control_constants_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.runtimeOperationLease",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.runtimeStatus",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.runtimeEvents",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.runtimeObservabilityDB",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.runtimeObservation",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.vmLifecycle",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.vmIPFile",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.vmConfig",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.runtimeVersion",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.guestRuntimeConfig",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.proxyLaunchDaemon",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.proxyNginxConfig",
            log_export_sources_text,
        ),
        (
            relative(log_export_sources_path),
            "RuntimeControlClientConstants.Paths.proxyNginxPid",
            log_export_sources_text,
        ),
        (
            relative(mac_local_api_path),
            "JSONFileRuntimeOperationLeaseRepository(",
            mac_local_api_text,
        ),
        (
            relative(mac_local_api_path),
            "InstalledRuntimePaths.defaultInstalled.runtimeOperationLease",
            mac_local_api_text,
        ),
        (
            relative(operation_lease_race_troubleshooting_path),
            'cat "/Library/Application Support/TiroshVitalServer/status/runtime-operation-lease.json"',
            operation_lease_race_troubleshooting_text,
        ),
        (
            relative(update_shutdown_troubleshooting_path),
            'cat "/Library/Application Support/VitalServerHelper/status/runtime-operation-lease.json"',
            update_shutdown_troubleshooting_text,
        ),
    ]
    present = [
        f"{path}:{token}"
        for path, token, text in forbidden
        if token in text
    ]
    if missing or present:
        return CheckResult(
            "cli-host-centralized-operation-lease-owner-adapter",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "cli-host-centralized-operation-lease-owner-adapter",
        True,
        "Host CLI operation lease adapter selection is centralized behind the owner contract",
    )


def check_host_vm_lifecycle_has_runtime_control_api_owner_surface() -> CheckResult:
    endpoint_routing_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpointRouting.swift"
    )
    read_routes_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlHTTPReadRoutes.swift"
    )
    command_routes_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlHTTPCommandRoutes.swift"
    )
    requests_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIRequests.swift"
    )
    read_models_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlReadModels.swift"
    )
    api_handler_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent"
        / "MacRuntimeControlAPIHandler.swift"
    )
    mac_environment_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent"
        / "MacPlatformAgentService.swift"
    )
    controller_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent"
        / "RuntimeControlVMLifecycleController.swift"
    )
    outbound_client_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/RuntimeControlAPI"
        / "RuntimeControlAPIVMLifecycleOwner.swift"
    )
    resource_reader_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeVMLifecycleResourceReaders.swift"
    )
    mac_client_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Client"
        / "MacRuntimeControlClient.swift"
    )
    legacy_store_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Persistence"
        / "RuntimeVMLifecycleStore.swift"
    )
    legacy_store_tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests"
        / "RuntimeVMLifecycleStoreTests.swift"
    )
    provider_store_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Persistence"
        / "FileRuntimeVMLifecycleResourceStore.swift"
    )
    provider_store_tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests"
        / "FileRuntimeVMLifecycleResourceStoreTests.swift"
    )
    status_owner_readers_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeHostStatusOwnerReaders.swift"
    )
    health_checker_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Health"
        / "RuntimeHealthChecker.swift"
    )
    lifecycle_composition_path = (
        MACOS_RUNTIME
        / "Sources/Bootstrap/DI"
        / "RuntimeLifecycleComposition.swift"
    )
    api_tests_path = (
        MACOS_RUNTIME
        / "Tests/InboundAdaptersTests/RuntimeControlAPI"
        / "RuntimeControlAPITests.swift"
    )
    controller_tests_path = (
        MACOS_RUNTIME
        / "Tests/MacControlPanelHostTests"
        / "RuntimeControlVMLifecycleControllerTests.swift"
    )
    outbound_client_tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests"
        / "RuntimeControlAPIVMLifecycleOwnerTests.swift"
    )
    watchdog_composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeWatchdogRunnerComposition.swift"
    )
    cli_lifecycle_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeLifecycle.swift"
    )
    launcher_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/Entrypoint"
        / "Launcher.swift"
    )
    vm_delegate_composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "VirtualMachineDelegate.swift"
    )
    vm_termination_composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "VirtualMachineTerminationHandler.swift"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    api_docs_path = ROOT / "docs/runtime/macos/runtime-control-api.md"
    guest_control_docs_path = ROOT / "docs/runtime/macos/runtime-guest-control.md"
    texts = {
        relative(endpoint_routing_path): read(endpoint_routing_path),
        relative(read_routes_path): read(read_routes_path),
        relative(command_routes_path): read(command_routes_path),
        relative(requests_path): read(requests_path),
        relative(read_models_path): read(read_models_path),
        relative(api_handler_path): read(api_handler_path),
        relative(mac_environment_path): read(mac_environment_path),
        relative(controller_path): read(controller_path),
        relative(outbound_client_path): read(outbound_client_path),
        relative(resource_reader_path): read(resource_reader_path),
        relative(mac_client_path): read(mac_client_path),
        relative(status_owner_readers_path): read(status_owner_readers_path),
        relative(health_checker_path): read(health_checker_path),
        relative(lifecycle_composition_path): read(lifecycle_composition_path),
        relative(api_tests_path): read(api_tests_path),
        relative(controller_tests_path): read(controller_tests_path),
        relative(outbound_client_tests_path): read(outbound_client_tests_path),
        relative(watchdog_composition_path): read(watchdog_composition_path),
        relative(cli_lifecycle_path): read(cli_lifecycle_path),
        relative(launcher_path): read(launcher_path),
        relative(vm_delegate_composition_path): read(vm_delegate_composition_path),
        relative(vm_termination_composition_path): read(vm_termination_composition_path),
        relative(openapi_path): read(openapi_path),
        relative(api_docs_path): read(api_docs_path),
        relative(guest_control_docs_path): read(guest_control_docs_path),
        relative(provider_store_path): read(provider_store_path),
        relative(provider_store_tests_path): read(provider_store_tests_path),
    }
    required = [
        (relative(endpoint_routing_path), 'path: "/platform/runtime-provider", scope: .platformAffordance'),
        (relative(read_routes_path), "handler.loadVMLifecycleResource()"),
        (relative(command_routes_path), "handler.putVMLifecycleResource(lifecycleRequest)"),
        (relative(requests_path), "public struct RuntimeVMLifecyclePutRequest"),
        (relative(read_models_path), "public enum RuntimeHostResourceReadState"),
        (relative(read_models_path), "case missing"),
        (relative(read_models_path), "public struct RuntimeVMLifecycleResourceState"),
        (relative(api_handler_path), "protocol RuntimeVMLifecycleResourceClient"),
        (relative(api_handler_path), "vmLifecycleClient.putVMLifecycleResource(request.document)"),
        (relative(mac_environment_path), "RuntimeControlVMLifecycleController("),
        (relative(controller_path), "final class RuntimeControlVMLifecycleController"),
        (relative(controller_path), "FileRuntimeVMLifecycleResourceStore("),
        (relative(provider_store_path), "public struct FileRuntimeVMLifecycleResourceStore"),
        (relative(provider_store_path), "RuntimeVMLifecycleResourceReading"),
        (relative(provider_store_path), "RuntimeVMLifecycleResourceWriting"),
        (relative(provider_store_path), "options: .atomic"),
        (relative(provider_store_tests_path), "testWritePersistsLifecycleForAnotherReader"),
        (relative(provider_store_tests_path), "testInvalidDocumentStaysFailedInsteadOfMissing"),
        (relative(outbound_client_path), "public struct RuntimeControlAPIVMLifecycleOwner"),
        (relative(outbound_client_path), 'path: "/platform/runtime-provider"'),
        (relative(outbound_client_path), "invalidVMLifecycleState"),
        (relative(resource_reader_path), "public protocol RuntimeVMLifecycleResourceReading"),
        (relative(resource_reader_path), "public struct RuntimeControlAPIVMLifecycleResourceReader"),
        (relative(resource_reader_path), "public struct RuntimeControlAPIVMLifecycleResourceWriter"),
        (relative(resource_reader_path), "public struct UnavailableRuntimeVMLifecycleResourceReader"),
        (relative(resource_reader_path), "enum RuntimeVMLifecycleResourceReadMapper"),
        (relative(mac_environment_path), "vmLifecycleResourceReader: vmLifecycleController"),
        (relative(mac_client_path), "platformStateReader: Self.livePlatformStateReader()"),
        (relative(mac_client_path), "vmLifecycleResourceReader: any RuntimeVMLifecycleResourceReading"),
        (relative(mac_client_path), "vmLifecycleResourceReader: RuntimeControlAPIVMLifecycleResourceReader()"),
        (relative(status_owner_readers_path), "RuntimeVMLifecycleResourceReadMapper.statusRead"),
        (relative(health_checker_path), "RuntimeVMLifecycleResourceReadMapper.loadResult"),
        (relative(lifecycle_composition_path), "vmLifecycleResourceReader: RuntimeControlAPIVMLifecycleResourceReader()"),
        (relative(launcher_path), "FileRuntimeVMLifecycleResourceStore("),
        (relative(launcher_path), "documentURL: paths.installed.vmLifecycle"),
        (relative(launcher_path), "writeVMLifecycleResource"),
        (relative(vm_delegate_composition_path), "lifecycleWriter: any RuntimeVMLifecycleResourceWriting"),
        (relative(vm_termination_composition_path), "lifecycleWriter: any RuntimeVMLifecycleResourceWriting"),
        (relative(api_tests_path), "testRouterServesAndUpdatesHostVMLifecycleResourceWithoutLoadingStatus"),
        (relative(controller_tests_path), "testLoadReportsMissingDistinctly"),
        (relative(outbound_client_tests_path), "testHTTPFailureDoesNotBecomeMissingResource"),
        (relative(watchdog_composition_path), "FileRuntimeVMLifecycleResourceStore("),
        (relative(cli_lifecycle_path), "FileRuntimeVMLifecycleResourceStore("),
        (relative(cli_lifecycle_path), "skipped VM lifecycle stopped write after process stop"),
        (relative(openapi_path), '"/platform/runtime-provider"'),
        (relative(openapi_path), '"RuntimeProviderResourceState"'),
        (relative(api_docs_path), "`GET /platform/runtime-provider`"),
        (relative(api_docs_path), "`PUT /platform/runtime-provider`"),
        (relative(guest_control_docs_path), "`GET`/`PUT /platform/runtime-provider`"),
    ]
    missing = [
        f"{path}:{token}"
        for path, token in required
        if token not in texts[path]
    ]
    if missing:
        return CheckResult(
            "host-vm-lifecycle-runtime-control-api-owner-surface",
            False,
            f"missing={missing}",
        )
    if legacy_store_path.exists() or legacy_store_tests_path.exists():
        return CheckResult(
            "host-vm-lifecycle-runtime-control-api-owner-surface",
            False,
            "legacy RuntimeVMLifecycleStore file-backed current state adapter still exists",
        )
    if "RuntimeVMLifecycleStore(" in texts[relative(watchdog_composition_path)]:
        return CheckResult(
            "host-vm-lifecycle-runtime-control-api-owner-surface",
            False,
            "RuntimeWatchdogRunnerComposition still writes VM lifecycle through RuntimeVMLifecycleStore",
        )
    for path in [relative(status_owner_readers_path), relative(health_checker_path)]:
        if "RuntimeVMLifecycleStore(" in texts[path]:
            return CheckResult(
                "host-vm-lifecycle-runtime-control-api-owner-surface",
                False,
                f"{path} still reads VM lifecycle through RuntimeVMLifecycleStore",
            )
    for path in [
        relative(launcher_path),
        relative(vm_delegate_composition_path),
        relative(vm_termination_composition_path),
    ]:
        if "RuntimeVMLifecycleStore(" in texts[path]:
            return CheckResult(
                "host-vm-lifecycle-runtime-control-api-owner-surface",
                False,
                f"{path} still writes VM lifecycle through RuntimeVMLifecycleStore",
            )
    if "RuntimeVMLifecycleStore(" in texts[relative(cli_lifecycle_path)]:
        return CheckResult(
            "host-vm-lifecycle-runtime-control-api-owner-surface",
            False,
            "RuntimeLifecycle still writes VM lifecycle through RuntimeVMLifecycleStore",
        )
    for token in [
        "initialDocument:",
        "initialDocument: RuntimeVMLifecycleDocument?",
    ]:
        if token in texts[relative(controller_path)]:
            return CheckResult(
                "host-vm-lifecycle-runtime-control-api-owner-surface",
                False,
                f"VM lifecycle controller can still seed current owner state during construction: {token}",
            )
    return CheckResult(
        "host-vm-lifecycle-runtime-control-api-owner-surface",
        True,
        "Host VM lifecycle has a Runtime Control API owner resource surface with explicit missing/failed/loaded states",
    )


def check_host_guest_address_has_runtime_control_api_owner_surface() -> CheckResult:
    endpoint_routing_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlAPIEndpointRouting.swift"
    )
    read_routes_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlHTTPReadRoutes.swift"
    )
    command_routes_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlHTTPCommandRoutes.swift"
    )
    requests_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlAPIRequests.swift"
    )
    read_models_path = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlReadModels.swift"
    )
    api_handler_path = (
        MACOS_RUNTIME / "Sources/Hosts/MacPlatformAgent/MacRuntimeControlAPIHandler.swift"
    )
    mac_environment_path = (
        MACOS_RUNTIME / "Sources/Hosts/MacPlatformAgent/MacPlatformAgentService.swift"
    )
    controller_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/MacPlatformAgent/RuntimeControlGuestAddressController.swift"
    )
    durable_store_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Persistence/FileRuntimeGuestAddressResourceStore.swift"
    )
    durable_store_tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests/FileRuntimeGuestAddressResourceStoreTests.swift"
    )
    proxy_path = MACOS_RUNTIME / "Support/Packaging/proxy-run.template"
    outbound_client_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/RuntimeControlAPI/RuntimeControlAPIGuestAddressOwner.swift"
    )
    resource_reader_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeGuestAddressResourceReaders.swift"
    )
    mac_client_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Client"
        / "MacRuntimeControlClient.swift"
    )
    bootstrap_provider_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Environment"
        / "RuntimeBootstrapGuestAddressProvider.swift"
    )
    vm_ip_provider_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/Health/RuntimeVMIPFileGuestAddressProvider.swift"
    )
    status_owner_readers_path = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads/RuntimeHostStatusOwnerReaders.swift"
    )
    api_tests_path = (
        MACOS_RUNTIME / "Tests/InboundAdaptersTests/RuntimeControlAPI/RuntimeControlAPITests.swift"
    )
    controller_tests_path = (
        MACOS_RUNTIME
        / "Tests/MacControlPanelHostTests/RuntimeControlGuestAddressControllerTests.swift"
    )
    outbound_client_tests_path = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests/RuntimeControlAPIGuestAddressOwnerTests.swift"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    api_docs_path = ROOT / "docs/runtime/macos/runtime-control-api.md"
    guest_control_docs_path = ROOT / "docs/runtime/macos/runtime-guest-control.md"
    vm_ip_troubleshooting_path = ROOT / "docs/troubleshooting/017_vm-ip-waiting-bootstrap.md"
    texts = {
        relative(endpoint_routing_path): read(endpoint_routing_path),
        relative(read_routes_path): read(read_routes_path),
        relative(command_routes_path): read(command_routes_path),
        relative(requests_path): read(requests_path),
        relative(read_models_path): read(read_models_path),
        relative(api_handler_path): read(api_handler_path),
        relative(mac_environment_path): read(mac_environment_path),
        relative(controller_path): read(controller_path),
        relative(durable_store_path): read(durable_store_path),
        relative(durable_store_tests_path): read(durable_store_tests_path),
        relative(proxy_path): read(proxy_path),
        relative(outbound_client_path): read(outbound_client_path),
        relative(resource_reader_path): read(resource_reader_path),
        relative(mac_client_path): read(mac_client_path),
        relative(status_owner_readers_path): read(status_owner_readers_path),
        relative(api_tests_path): read(api_tests_path),
        relative(controller_tests_path): read(controller_tests_path),
        relative(outbound_client_tests_path): read(outbound_client_tests_path),
        relative(openapi_path): read(openapi_path),
        relative(api_docs_path): read(api_docs_path),
        relative(guest_control_docs_path): read(guest_control_docs_path),
        relative(vm_ip_troubleshooting_path): read(vm_ip_troubleshooting_path),
    }
    required = [
        (relative(endpoint_routing_path), 'path: "/platform/runtime-endpoint", scope: .platformAffordance'),
        (relative(read_routes_path), "handler.loadGuestAddressResource()"),
        (relative(command_routes_path), "handler.putGuestAddressResource(guestAddressRequest)"),
        (relative(requests_path), "public struct RuntimeGuestAddressPutRequest"),
        (relative(read_models_path), "public struct RuntimeGuestAddressResourceState"),
        (relative(api_handler_path), "protocol RuntimeGuestAddressResourceClient"),
        (relative(api_handler_path), "guestAddressClient.putGuestAddressResource(address: request.address)"),
        (relative(mac_environment_path), "RuntimeControlGuestAddressController("),
        (relative(controller_path), "final class RuntimeControlGuestAddressController"),
        (relative(controller_path), "any RuntimeGuestAddressResourceReading"),
        (relative(controller_path), "any RuntimeGuestAddressResourceWriting"),
        (relative(durable_store_path), "public struct FileRuntimeGuestAddressResourceStore"),
        (relative(durable_store_path), "options: .atomic"),
        (relative(durable_store_path), "source: .platformAgent"),
        (relative(durable_store_tests_path), "testPutPersistsEndpointForAnotherReader"),
        (relative(proxy_path), 'runtime_endpoint_file="${vm_home}/run/runtime-endpoint.json"'),
        (relative(proxy_path), "publish_runtime_endpoint()"),
        (relative(proxy_path), '"source":"platform-agent"'),
        (relative(outbound_client_path), "public struct RuntimeControlAPIGuestAddressOwner"),
        (relative(outbound_client_path), 'path: "/platform/runtime-endpoint"'),
        (relative(outbound_client_path), "invalidGuestAddressState"),
        (relative(resource_reader_path), "public struct RuntimeControlAPIGuestAddressProvider"),
        (relative(resource_reader_path), "RuntimeGuestAddressResourceReadMapper.readResult"),
        (relative(mac_environment_path), "guestAddressProvider: runtimeEndpointStore"),
        (relative(mac_client_path), "platformStateReader: Self.livePlatformStateReader()"),
        (relative(mac_client_path), "guestAddressProvider: any RuntimeGuestAddressProvider"),
        (relative(mac_client_path), "guestAddressProvider: RuntimeControlAPIGuestAddressProvider()"),
        (relative(status_owner_readers_path), "UnavailableRuntimeGuestAddressProvider("),
        (relative(api_tests_path), "testRouterServesAndUpdatesHostGuestAddressResourceWithoutLoadingStatus"),
        (relative(controller_tests_path), "testPutAndLoadPreserveExplicitOwnerAddress"),
        (relative(outbound_client_tests_path), "testHTTPFailureDoesNotBecomeMissingResource"),
        (relative(openapi_path), '"/platform/runtime-endpoint"'),
        (relative(openapi_path), '"RuntimeEndpointResourceState"'),
        (relative(api_docs_path), "`GET /platform/runtime-endpoint`"),
        (relative(api_docs_path), "`PUT /platform/runtime-endpoint`"),
        (relative(guest_control_docs_path), "`vm/run/runtime-endpoint.json` is the durable owner document"),
        (relative(vm_ip_troubleshooting_path), "durable runtime endpoint owner (`vm/run/runtime-endpoint.json`)"),
        (relative(vm_ip_troubleshooting_path), "Platform proxy adapter explicitly promotes into the owner document"),
    ]
    missing = [
        f"{path}:{token}"
        for path, token in required
        if token not in texts[path]
    ]
    if missing:
        return CheckResult(
            "host-guest-address-runtime-control-api-owner-surface",
            False,
            f"missing={missing}",
        )
    legacy_files = [
        relative(path)
        for path in [bootstrap_provider_path, vm_ip_provider_path]
        if path.exists()
    ]
    if legacy_files:
        return CheckResult(
            "host-guest-address-runtime-control-api-owner-surface",
            False,
            f"legacy vm-ip Guest address providers still exist: {legacy_files}",
        )
    for path in [relative(status_owner_readers_path), relative(api_handler_path), relative(mac_environment_path)]:
        if "RuntimeVMIPFileGuestAddressProvider(" in texts[path]:
            return CheckResult(
                "host-guest-address-runtime-control-api-owner-surface",
                False,
                f"{path} still selects vm-ip file provider as current Guest address owner",
            )
        if "RuntimeBootstrapGuestAddressProvider.live(" in texts[path]:
            return CheckResult(
                "host-guest-address-runtime-control-api-owner-surface",
                False,
                f"{path} still seeds current Guest address owner from vm-ip bootstrap evidence",
            )
    for token in [
        "seedProvider:",
        "seedProvider: (any RuntimeGuestAddressProvider)?",
    ]:
        if token in texts[relative(controller_path)]:
            return CheckResult(
                "host-guest-address-runtime-control-api-owner-surface",
                False,
                f"Guest address controller can still seed current owner state during construction: {token}",
            )
    for token in [
        "explicit Guest address provider (`vm/data/run/vm-ip`)",
        "Current Host reads should prefer",
    ]:
        if token in texts[relative(vm_ip_troubleshooting_path)]:
            return CheckResult(
                "host-guest-address-runtime-control-api-owner-surface",
                False,
                f"{relative(vm_ip_troubleshooting_path)} still describes vm-ip evidence as the current provider: {token}",
            )
    return CheckResult(
        "host-guest-address-runtime-control-api-owner-surface",
        True,
        "Platform runtime endpoint has a durable owner repository exposed through the API with explicit missing/failed/loaded states",
    )


def check_guest_bootstrap_result_is_not_current_state_input() -> CheckResult:
    guard_composition_path = (
        MACOS_RUNTIME
        / "Sources/Hosts/CLI/ProcessBoundary"
        / "RuntimeManagedOperationGuardComposition.swift"
    )
    guard_usecase_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeHealth"
        / "GuardManagedRuntimeOperationUseCase.swift"
    )
    watchdog_path = (
        MACOS_RUNTIME
        / "Sources/Application/UseCases/RuntimeHealth"
        / "WatchdogRuntimeUseCase.swift"
    )
    guard_composition = read(guard_composition_path)
    texts = {
        relative(guard_composition_path): guard_composition,
        relative(guard_usecase_path): read(guard_usecase_path),
        relative(watchdog_path): read(watchdog_path),
    }
    deleted_paths = [
        (
            MACOS_RUNTIME
            / "Sources/Domain/Policies/GuestBootstrapEvaluator.swift"
        ),
        (
            MACOS_RUNTIME
            / "Sources/Adapters/Outbound/Persistence"
            / "JSONFileRuntimeGuestDocumentReader.swift"
        ),
    ]
    forbidden = {
        path: [
            "GuestBootstrapEvaluator",
            "GuestBootstrapAssessment",
            "RuntimeGuestBootstrapResultReader",
            "JSONFileRuntimeGuestDocumentReader",
            "loadBootstrapResultDocument",
            "guestBootstrapManagedOperationGuardPlan",
            "activeGuestBootstrap",
            "RuntimeGuestBootstrapOperation",
        ]
        for path in texts
    }
    existing_deleted_paths = [relative(path) for path in deleted_paths if path.exists()]
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in texts[path]
    ]
    if existing_deleted_paths or present:
        return CheckResult(
            "guest-bootstrap-result-not-current-state-input",
            False,
            f"deleted_paths_present={existing_deleted_paths} forbidden_present={present}",
        )
    return CheckResult(
        "guest-bootstrap-result-not-current-state-input",
        True,
        "bootstrap-result artifacts are not wired into current health, guard, "
        "or watchdog state decisions",
    )


def check_recorder_ingress_status_read_result_preserves_explicit_read_contract() -> CheckResult:
    swift_contract = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeHealthObservationReads.swift"
    )
    swift_contract_tests = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    pwa_schema = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    pwa_schema_tests = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts"
    )
    openapi = ROOT / "docs/runtime/runtime-control.openapi.json"
    texts = {
        relative(swift_contract): read(swift_contract),
        relative(swift_contract_tests): read(swift_contract_tests),
        relative(pwa_schema): read(pwa_schema),
        relative(pwa_schema_tests): read(pwa_schema_tests),
        relative(openapi): read(openapi),
    }
    swift_recorder_ingress_text = text_between(
        texts[relative(swift_contract)],
        "public struct RuntimeRecorderIngressStatusReadResult",
        "public enum RuntimeRedisRelayStatusReadState",
    )
    required = {
        relative(swift_contract): [
            "let readState = try container.decode(RuntimeRecorderIngressStatusReadState.self, forKey: .readState)",
            "let httpStatus = try container.decode(String.self, forKey: .httpStatus)",
            "let document = try container.decodeRequiredNullable(",
            "let readError = try container.decodeRequiredNullable(String.self, forKey: .readError)",
            "loaded recorder ingress status reads must include document",
            "recorder ingress status reads must include readError",
        ],
        relative(swift_contract_tests): [
            "testRecorderIngressStatusReadResultEncodesExplicitReadEvidence",
            "loaded recorder ingress status reads must include document",
            "readFailed recorder ingress status reads must include readError",
        ],
        relative(pwa_schema): [
            "loaded recorder ingress status reads must include document",
            "recorder ingress status reads must include readError",
        ],
        relative(pwa_schema_tests): [
            'readState: "readFailed"',
            'readError: ""',
        ],
        relative(openapi): [
            "\"RuntimeRecorderIngressStatusReadResult\"",
            "\"readState\"",
            "\"httpStatus\"",
            "\"document\"",
            "\"readError\"",
        ],
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = {
        relative(swift_contract): [
            "let httpStatus = try container.decodeIfPresent(String.self, forKey: .httpStatus) ?? \"\"",
            "let document = try container.decodeIfPresent(RuntimeRecorderIngressStatusDocument.self, forKey: .document)",
            "let readError = try container.decodeIfPresent(String.self, forKey: .readError)",
            "readState: try container.decodeIfPresent(",
        ],
        relative(swift_contract_tests): [
            "legacy read failed",
            "XCTAssertEqual(legacy.httpStatus, \"\")",
        ],
    }
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in (swift_recorder_ingress_text if path == relative(swift_contract) else texts[path])
    ]
    if missing or present:
        return CheckResult(
            "recorder-ingress-status-read-result-explicit-contract",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "recorder-ingress-status-read-result-explicit-contract",
        True,
        "Recorder ingress status read results require explicit read state, http status, nullable document, and nullable read error",
    )


def check_redis_relay_status_read_result_preserves_explicit_read_contract() -> CheckResult:
    swift_contract = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeHealthObservationReads.swift"
    )
    swift_contract_tests = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    texts = {
        relative(swift_contract): read(swift_contract),
        relative(swift_contract_tests): read(swift_contract_tests),
    }
    swift_redis_relay_text = text_between(
        texts[relative(swift_contract)],
        "public struct RuntimeRedisRelayStatusReadResult",
        "public struct RuntimeHostProxyListenerObservation",
    )
    required = {
        relative(swift_contract): [
            "let readState = try container.decode(RuntimeRedisRelayStatusReadState.self, forKey: .readState)",
            "let document = try container.decodeRequiredNullable(RuntimeRedisRelayStatus.self, forKey: .document)",
            "let readError = try container.decodeRequiredNullable(String.self, forKey: .readError)",
            "loaded Redis Relay status reads must include document",
            "Redis Relay status reads must include readError",
        ],
        relative(swift_contract_tests): [
            "testRedisRelayStatusReadResultEncodesExplicitReadEvidence",
            "loaded Redis Relay status reads must include document",
            "readFailed Redis Relay status reads must include readError",
        ],
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    forbidden = {
        relative(swift_contract): [
            "let document = try container.decodeIfPresent(RuntimeRedisRelayStatus.self, forKey: .document)",
            "let readError = try container.decodeIfPresent(String.self, forKey: .readError)",
            "readState: try container.decodeIfPresent(",
        ],
        relative(swift_contract_tests): [
            "legacy Redis Relay status",
        ],
    }
    present = [
        f"{path}:{token}"
        for path, tokens in forbidden.items()
        for token in tokens
        if token in (swift_redis_relay_text if path == relative(swift_contract) else texts[path])
    ]
    if missing or present:
        return CheckResult(
            "redis-relay-status-read-result-explicit-contract",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "redis-relay-status-read-result-explicit-contract",
        True,
        "Redis Relay status read results require explicit read state, nullable document, and nullable read error",
    )


def check_redis_relay_status_document_preserves_complete_owner_contract() -> CheckResult:
    runtime_status_contract = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlModels.swift"
    )
    runtime_status_reader = (
        MACOS_RUNTIME
        / "Sources/Adapters/Outbound/MacRuntimeControlClient/Reads"
        / "RuntimeStatusReader.swift"
    )
    endpoint_routing = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary"
        / "RuntimeControlAPIEndpointRouting.swift"
    )
    swift_contract = (
        MACOS_RUNTIME
        / "Sources/Contracts/Shared/RuntimeRedisRelayStatus.swift"
    )
    swift_contract_tests = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    gateway_tests = (
        MACOS_RUNTIME
        / "Tests/OutboundAdaptersTests/HTTPRuntimeGuestControlGatewayTests.swift"
    )
    pwa_schema = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    pwa_schema_tests = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.test.ts"
    )
    pwa_generated = (
        PWA
        / "src/domain/runtime-control/contracts/generated/runtime-control.ts"
    )
    openapi = ROOT / "docs/runtime/runtime-control.openapi.json"
    guest_control_store = (
        GUEST_TOOLS
        / "src/tirosh_guest_tools/adapters/outbound/sqlite_control/repository.py"
    )
    guest_domain_models = (
        GUEST_TOOLS / "src/tirosh_guest_tools/domain/guest_control/models.py"
    )
    guest_api = (
        GUEST_TOOLS / "src/tirosh_guest_tools/adapters/inbound/guest_control_api.py"
    )
    guest_usecase = (
        GUEST_TOOLS / "src/tirosh_guest_tools/application/guest_control/usecases.py"
    )
    guest_control_store_tests = (
        GUEST_TOOLS / "tests/test_guest_control_sqlite_repository.py"
    )
    guest_api_tests = GUEST_TOOLS / "tests/test_guest_control_api.py"
    guest_usecase_tests = GUEST_TOOLS / "tests/test_guest_control_usecases.py"
    texts = {
        relative(runtime_status_contract): read(runtime_status_contract),
        relative(runtime_status_reader): read(runtime_status_reader),
        relative(endpoint_routing): read(endpoint_routing),
        relative(swift_contract): read(swift_contract),
        relative(swift_contract_tests): read(swift_contract_tests),
        relative(gateway_tests): read(gateway_tests),
        relative(pwa_schema): read(pwa_schema),
        relative(pwa_schema_tests): read(pwa_schema_tests),
        relative(pwa_generated): read(pwa_generated),
        relative(openapi): read(openapi),
        relative(guest_control_store): read(guest_control_store),
        relative(guest_domain_models): read(guest_domain_models),
        relative(guest_api): read(guest_api),
        relative(guest_usecase): read(guest_usecase),
        relative(guest_control_store_tests): read(guest_control_store_tests),
        relative(guest_api_tests): read(guest_api_tests),
        relative(guest_usecase_tests): read(guest_usecase_tests),
    }
    required = {
        relative(endpoint_routing): [
            'path: "/runtime/redis-relay/status"',
        ],
        relative(swift_contract): [
            "public var schemaVersion: Int",
            "schemaVersion: try container.decode(Int.self, forKey: .schemaVersion)",
            "observedAt: try container.decode(String.self, forKey: .observedAt)",
            "enabled: try container.decode(Bool.self, forKey: .enabled)",
            "state: try container.decode(String.self, forKey: .state)",
            "scope: try container.decodeRequiredNullable(String.self, forKey: .scope)",
            "targetUrl: try container.decodeRequiredNullable(String.self, forKey: .targetUrl)",
            "targetUsernameConfigured: try container.decode(",
            "targetPasswordConfigured: try container.decode(",
            "settingsFingerprint: try container.decodeRequiredNullable(",
            "batches: try container.decode(Int.self, forKey: .batches)",
            "totals: try container.decode(RuntimeRedisRelayBatch.self, forKey: .totals)",
            "lastBatch: try container.decodeRequiredNullable(RuntimeRedisRelayBatch.self, forKey: .lastBatch)",
            "lastSuccessAt: try container.decodeRequiredNullable(String.self, forKey: .lastSuccessAt)",
            "lastErrorAt: try container.decodeRequiredNullable(String.self, forKey: .lastErrorAt)",
            "lastError: try container.decodeRequiredNullable(String.self, forKey: .lastError)",
            "scanned: try container.decode(Int.self, forKey: .scanned)",
            "copied: try container.decode(Int.self, forKey: .copied)",
            "published: try container.decode(Int.self, forKey: .published)",
            "duplicates: try container.decode(Int.self, forKey: .duplicates)",
            "errors: try container.decode(Int.self, forKey: .errors)",
            "try encodeNil(forKey: key)",
        ],
        relative(swift_contract_tests): [
            "testRedisRelayStatusRequiresCompleteOwnerDocumentPayload",
            "XCTAssertTrue(encodedJSON[\"scope\"] is NSNull)",
            "XCTAssertTrue(encodedJSON[\"targetUrl\"] is NSNull)",
            "String(describing: error).contains(\"scope\")",
            "XCTAssertTrue(String(describing: error).contains(\"copied\"))",
        ],
        relative(gateway_tests): [
            "\"schemaVersion\": 1",
            "\"published\": 8",
            "\"duplicates\": 0",
            "\"lastBatch\": null",
            "\"lastSuccessAt\": null",
            "\"lastErrorAt\": null",
            "\"lastError\": null",
        ],
        relative(pwa_schema): [
            "const runtimeRedisRelayBatchSchema = z",
            "published: z.number().int()",
            "duplicates: z.number().int()",
            "const runtimeRedisRelayStatusSchema = z",
            "scope: requiredNullableString",
            "targetUrl: requiredNullableString",
            "settingsFingerprint: requiredNullableString",
            "lastBatch: runtimeRedisRelayBatchSchema.nullable()",
            "export const runtimeRedisRelayStatusReadResultSchema = z",
            '"Redis Relay status must be read from its Runtime owner resource"',
        ],
        relative(pwa_schema_tests): [
            "requires complete Redis Relay status owner resource documents",
            "scope: null",
            "toThrow(/scope/)",
            "published: 0",
            "duplicates: 0",
            "toThrow(/published/)",
        ],
        relative(pwa_generated): [
            "RuntimeRedisRelayBatch: {",
            "published: number;",
            "duplicates: number;",
            "RuntimeRedisRelayStatus: {",
            "scope: string | null;",
            '"/runtime/redis-relay/status": {',
            "RuntimeRedisRelayStatusReadResult: {",
        ],
        relative(openapi): [
            "\"RuntimeRedisRelayBatch\"",
            "\"RuntimeRedisRelayStatus\"",
            "\"published\"",
            "\"duplicates\"",
            '"/runtime/redis-relay/status"',
            '"RuntimeRedisRelayStatusReadResult"',
            "\"$ref\": \"#/components/schemas/RuntimeRedisRelayStatus\"",
        ],
        relative(guest_control_store): [
            "validate_redis_relay_status_document(document)",
            "except RedisRelayStatusContractError as error:",
            "kind=\"redis-relay-contract-invalid\"",
        ],
        relative(guest_domain_models): [
            "class RedisRelayStatusContractError",
            "REDIS_RELAY_REQUIRED_NULLABLE_STRING_FIELDS",
            "\"scope\"",
            "\"targetUrl\"",
            "\"settingsFingerprint\"",
            "\"lastSuccessAt\"",
            "\"lastErrorAt\"",
            "\"lastError\"",
            "REDIS_RELAY_BATCH_COUNTER_FIELDS",
            "\"published\"",
            "\"duplicates\"",
            "validate_redis_relay_batch(totals, field=\"totals\")",
            "validate_redis_relay_batch(last_batch, field=\"lastBatch\")",
        ],
        relative(guest_api): [
            "except RedisRelayStatusContractError as error:",
            "code=\"redisRelayStatusInvalid\"",
        ],
        relative(guest_usecase): [
            "validate_redis_relay_status_document(document)",
            "self._redis_relay.save_status(document)",
        ],
        relative(guest_control_store_tests): [
            "test_sqlite_control_store_records_operation_event_and_lease_atomically",
            "test_sqlite_control_store_rolls_back_operation_event_and_lease_together",
            "test_controller_restart_interrupts_unfinished_operation_and_releases_lease",
        ],
        relative(guest_api_tests): [
            "def redis_relay_status_document(",
            "\"schemaVersion\": 1",
            "\"scope\": \"vital_reconstruction\"",
            "\"published\": copied",
            "\"duplicates\": 0",
            "\"lastBatch\": None",
            "body = json.dumps(redis_relay_status_document()).encode(\"utf-8\")",
            "test_redis_relay_status_route_rejects_incomplete_owner_snapshot",
            "\"code\": \"redisRelayStatusInvalid\"",
            "assert operations.redis_relay_status is None",
        ],
        relative(guest_usecase_tests): [
            "def redis_relay_status_document(",
            "\"schemaVersion\": 1",
            "\"scope\": \"vital_reconstruction\"",
            "\"published\": copied",
            "\"duplicates\": 0",
            "\"lastBatch\": None",
            "usecases.put_redis_relay_status(redis_relay_status_document())",
            "\"document\": redis_relay_status_document(copied=1)",
            "test_redis_relay_status_owner_mutation_rejects_incomplete_snapshot",
            "RedisRelayStatusContractError",
            "totals.published",
        ],
    }
    missing = {
        path: [token for token in tokens if token not in texts[path]]
        for path, tokens in required.items()
        if any(token not in texts[path] for token in tokens)
    }
    repository_path = relative(guest_control_store)
    if texts[repository_path].count("validate_redis_relay_status_document(document)") < 2:
        missing.setdefault(repository_path, []).append(
            "validate_redis_relay_status_document(document) in save_status and status"
        )
    forbidden = {
        relative(runtime_status_contract): [
            "case redisRelayStatus",
            "public var redisRelayStatus:",
        ],
        relative(runtime_status_reader): [
            "redisRelayStatusRead(",
            ".redisRelayStatus()",
        ],
        relative(swift_contract): [
            "try container.decodeIfPresent(Int.self, forKey: .scanned) ?? 0",
            "try container.decodeIfPresent(Int.self, forKey: .copied) ?? 0",
            "try container.decodeIfPresent(Int.self, forKey: .published) ?? 0",
            "try container.decodeIfPresent(Int.self, forKey: .duplicates) ?? 0",
            "try container.decodeIfPresent(String.self, forKey: .observedAt) ?? \"\"",
            "try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false",
            "try container.decodeIfPresent(String.self, forKey: .state) ?? \"unknown\"",
            "try container.decodeIfPresent(String.self, forKey: .scope) ?? \"unknown\"",
            "scope: try container.decode(String.self, forKey: .scope)",
            "try container.decodeIfPresent(Int.self, forKey: .batches) ?? 0",
            "try container.decodeIfPresent(RuntimeRedisRelayBatch.self, forKey: .totals)",
            "?? RuntimeRedisRelayBatch()",
        ],
        relative(guest_control_store): [
            "observed_at = document.get(\"observedAt\")",
            "Redis relay status document is missing observedAt.",
        ],
        relative(guest_api_tests): [
            "\"totals\": {\"copied\": 8}",
            "\"totals\": {\"copied\": 1}",
        ],
        relative(guest_usecase_tests): [
            "\"totals\": {\"copied\": 8}",
            "\"totals\": {\"copied\": 1}",
        ],
        relative(pwa_generated): [
            'redisRelayStatus?: components["schemas"]["RuntimeRedisRelayStatus"] | null;',
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
            "redis-relay-status-document-complete-owner-contract",
            False,
            f"missing={missing} forbidden_present={present}",
        )
    return CheckResult(
        "redis-relay-status-document-complete-owner-contract",
        True,
        "Redis Relay status documents require complete owner-provided fields and explicit nullable values",
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
        ROOT / "docs/runtime/runtime-control.openapi.json",
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
        ROOT / "docs/recorder/send-data-flow-control.md",
    ]
    forbidden = [
        "RECORDER_INGRESS_RUNTIME_STATE_PATH",
        "RECORDER_INGRESS_RUNTIME_STATE_MAX_AGE_MS",
        "runtime-state-memory-guard-reader",
        "runtimeStatePath",
        "containerServices",
        "/run/tirosh/runtime/runtime-observation.json",
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
        "recorder-ingress no longer reads runtime-observation.json as a replay "
        "memory guard input",
    )


def check_runtime_boot_smoke_uses_guest_control_stack_status() -> CheckResult:
    path = GUEST_TOOLS / "src/tirosh_guest_tools/application/runtime_boot_smoke.py"
    text = read(path)
    required = [
        "/runtime/stack",
        "read_guest_control_stack_status",
        "observed_stack_services",
        "product-lab-recorder-flow",
        "LAB_REPLAY_SMOKE_VITAL_FILE",
        "/runtime/lab/vital-files/replay",
        "prepare_lab_replay_smoke_vital_file",
        "replaySessionId",
        '"guest-control-api"',
    ]
    forbidden = [
        "observed_compose_services",
        "runtime observation containerServices is missing or empty",
        "runtime observation is missing compose services",
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
        "runtime/proof/conformance:",
        "runtime/conformance:",
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
        "packages/vitalserver-devtools/tests/unit/test_runtime_v2_conformance.py",
        "scripts/runtime_v2_conformance.py",
        "pwa/check",
        "pwa/test",
        "pwa/build",
        'swift test --package-path "$(VM_SWIFT_PACKAGE_DIR)"',
        '"$(VM_RUNTIME_PROOF_SWIFT_FOCUSED_FILTER)"',
        "runtime/e2e/smoke",
        "runtime/proof/smoke",
        "Run focused Python Runtime v2 product/package tests",
        "Test the OS-neutral Platform/Runtime conformance rules",
        "Validate a live implementation at RUNTIME_V2_CONFORMANCE_BASE_URL",
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
        "Runtime v2 conformance, review, Swift focused, HTTP E2E, and VM "
        "smoke acceptance targets are explicit",
    )


def check_vitaldb_beds_use_explicit_bed_read_document() -> CheckResult:
    read_routes = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/RuntimeControlAPI/Boundary/RuntimeControlHTTPReadRoutes.swift"
    )
    beds_page = PWA / "src/pages/beds/BedsPage.tsx"
    runtime_control_types = (
        PWA / "src/domain/runtime-control/contracts/runtimeControlTypes.ts"
    )
    schema_path = (
        PWA
        / "src/domain/runtime-control/contracts/schemas/runtimeControlSchemas.ts"
    )
    runtime_view_model = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/ViewModels/RuntimeViewModel.swift"
    )
    runtime_refresher = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Refresh/RuntimeObservabilityRefresher.swift"
    )
    runtime_beds_panel = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Views/RuntimeBedsPanel.swift"
    )
    runtime_recorders_panel = (
        MACOS_RUNTIME
        / "Sources/Adapters/Inbound/MacControlPanel/Presentation/Views/RuntimeRecordersPanel.swift"
    )
    swift_read_models = (
        MACOS_RUNTIME
        / "Sources/Contracts/RuntimeControl/RuntimeControlReadModels.swift"
    )
    swift_contract_tests = (
        MACOS_RUNTIME
        / "Tests/RuntimeControlTests/RuntimeControlContractsTests.swift"
    )
    openapi_path = ROOT / "docs/runtime/runtime-control.openapi.json"
    route_text = read(read_routes)
    page_text = read(beds_page)
    types_text = read(runtime_control_types)
    schema_text = read(schema_path)
    runtime_view_model_text = read(runtime_view_model)
    runtime_refresher_text = read(runtime_refresher)
    runtime_beds_panel_text = read(runtime_beds_panel)
    runtime_recorders_panel_text = read(runtime_recorders_panel)
    swift_read_models_text = read(swift_read_models)
    swift_activity_history_text = text_between(
        swift_read_models_text,
        "public struct RuntimeVitalRecorderActivityHistory",
        "public enum RuntimeVitalRecorderActivityHistorySource",
    )
    swift_contract_tests_text = read(swift_contract_tests)
    openapi_text = read(openapi_path)

    missing = []
    if "handler.loadVitalDBBeds()" not in route_text:
        missing.append("RuntimeControlHTTPReadRoutes.loadVitalDBBeds")
    if "useVitalDBBeds" not in page_text:
        missing.append("BedsPage.useVitalDBBeds")
    if "z.infer<typeof vitalDBBedsSchema>" not in types_text:
        missing.append("VitalDBBeds.zod-inferred-type")
    if "export const vitalDBBedsSchema = z" not in schema_text or "beds: z.array" not in schema_text:
        missing.append("vitalDBBedsSchema.document")
    if '"$ref": "#/components/schemas/RuntimeVitalBedHistory"' not in openapi_text:
        missing.append("OpenAPI.RuntimeVitalBedHistory")
    if "@Published var vitalBeds = RuntimeVitalBedHistory()" not in runtime_view_model_text:
        missing.append("RuntimeViewModel.vitalBeds")
    if "let beds = await snapshots.loadVitalBeds()" not in runtime_refresher_text:
        missing.append("RuntimeObservabilityRefresher.loadVitalBeds")
    if "vitalBeds = refreshed.beds" not in runtime_view_model_text:
        missing.append("RuntimeViewModel.assign-refreshed-beds")
    if "viewModel.vitalBeds.beds" not in runtime_beds_panel_text:
        missing.append("RuntimeBedsPanel.vitalBeds")
    if "viewModel.vitalBeds.beds" not in runtime_recorders_panel_text:
        missing.append("RuntimeRecordersPanel.linked-bed-vitalBeds")
    if "recorders = try container.decode([RuntimeVitalRecorderRecord].self, forKey: .recorders)" not in swift_read_models_text:
        missing.append("RuntimeVitalRecorderHistory.required-recorders-array")
    if "beds = try container.decode([RuntimeVitalBedRecord].self, forKey: .beds)" not in swift_read_models_text:
        missing.append("RuntimeVitalRecorderHistory.required-beds-array")
    for label, token in [
        (
            "RuntimeVitalRecorderHistory.required-state",
            "state = try container.decode(RuntimeVitalRecorderHistoryState.self, forKey: .state)",
        ),
        (
            "RuntimeVitalRecorderHistory.required-summary",
            "summary = try container.decode(RuntimeVitalRecorderHistorySummary.self, forKey: .summary)",
        ),
        (
            "RuntimeVitalRecorderHistory.required-activity-history",
            "activityHistory = try container.decode(",
        ),
        (
            "RuntimeVitalRecorderActivityHistory.required-nullable-earliest-bucket",
            "earliestBucketStartedAt = try container.decodeRequiredNullable(",
        ),
        (
            "RuntimeVitalRecorderActivityHistory.required-nullable-latest-bucket",
            "latestBucketStartedAt = try container.decodeRequiredNullable(",
        ),
        (
            "RuntimeVitalRecorderActivityHistory.required-nullable-read-error",
            "readError = try container.decodeRequiredNullable(String.self, forKey: .readError)",
        ),
        (
            "RuntimeVitalRecorderHistory.required-nullable-recorder-ingress",
            "recorderIngressStatusRead = try container.decodeRequiredNullable(",
        ),
        (
            "RuntimeVitalBedHistory.required-nullable-updated-at",
            "updatedAt = try container.decodeRequiredNullable(String.self, forKey: .updatedAt)",
        ),
        (
            "RuntimeVitalBedHistory.explicit-null-encoding",
            "try container.encodeNil(forKey: .readError)",
        ),
    ]:
        if token not in swift_read_models_text:
            missing.append(label)
    if "testVitalRecorderHistoryRequiresCompleteReadDocumentPayload" not in swift_contract_tests_text:
        missing.append("RuntimeControlContractsTests.required-vital-recorder-document")
    if "testVitalRecorderActivityHistoryRequiresExplicitNullableFields" not in swift_contract_tests_text:
        missing.append("RuntimeControlContractsTests.required-vital-recorder-activity-history")
    if "testVitalBedHistoryPreservesExplicitNullableFieldsAndRequiresCompletePayload" not in swift_contract_tests_text:
        missing.append("RuntimeControlContractsTests.required-vital-bed-document")

    forbidden = []
    if "handler.loadVitalDBRecorders().beds" in route_text:
        forbidden.append("RuntimeControlHTTPReadRoutes.recorder-history-beds-slice")
    if "useVitalDBRecorders" in page_text:
        forbidden.append("BedsPage.useVitalDBRecorders")
    if "export const vitalDBBedsSchema = z.array" in schema_text:
        forbidden.append("vitalDBBedsSchema.array")
    if "vitalRecorders.beds" in runtime_beds_panel_text:
        forbidden.append("RuntimeBedsPanel.vitalRecorders.beds")
    if "vitalRecorders.beds" in runtime_recorders_panel_text:
        forbidden.append("RuntimeRecordersPanel.vitalRecorders.beds")
    if "recorders = try container.decodeIfPresent([RuntimeVitalRecorderRecord].self, forKey: .recorders) ?? []" in swift_read_models_text:
        forbidden.append("RuntimeVitalRecorderHistory.recorders-missing-defaults-empty")
    if "beds = try container.decodeIfPresent([RuntimeVitalBedRecord].self, forKey: .beds) ?? []" in swift_read_models_text:
        forbidden.append("RuntimeVitalRecorderHistory.beds-missing-defaults-empty")
    if "summary = try container.decodeIfPresent(RuntimeVitalRecorderHistorySummary.self, forKey: .summary)" in swift_read_models_text:
        forbidden.append("RuntimeVitalRecorderHistory.summary-missing-computed")
    if "activityHistory = try container.decodeIfPresent(" in swift_read_models_text:
        forbidden.append("RuntimeVitalRecorderHistory.activity-history-missing-not-provided")
    if "earliestBucketStartedAt = try container.decodeIfPresent(String.self, forKey: .earliestBucketStartedAt)" in swift_activity_history_text:
        forbidden.append("RuntimeVitalRecorderActivityHistory.earliest-bucket-missing-defaults-nil")
    if "latestBucketStartedAt = try container.decodeIfPresent(String.self, forKey: .latestBucketStartedAt)" in swift_activity_history_text:
        forbidden.append("RuntimeVitalRecorderActivityHistory.latest-bucket-missing-defaults-nil")
    if "state = try container.decodeIfPresent(RuntimeVitalRecorderHistoryState.self, forKey: .state)" in swift_read_models_text:
        forbidden.append("RuntimeVitalRecorderHistory.state-missing-computed")

    if missing or forbidden:
        return CheckResult(
            "vitaldb-beds-explicit-bed-read-document",
            False,
            f"missing={missing} forbidden={forbidden}",
        )
    return CheckResult(
        "vitaldb-beds-explicit-bed-read-document",
        True,
        "Runtime Control and PWA Beds read paths consume explicit Guest/Postgres Bed history documents",
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
