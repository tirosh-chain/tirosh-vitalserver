import Foundation
import Contracts
import XCTest

final class ContractsTests: XCTestCase {
    func testDecodesRuntimeStatusV1() throws {
        let document = try decodeFixture(RuntimeStatusDocument.self, named: "runtime-status-v1-healthy")

        XCTAssertNil(document.schemaVersion)
        XCTAssertEqual(document.status, .healthy)
        XCTAssertEqual(document.operation, .health)
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertNil(document.vmState)
        XCTAssertNil(document.vmErrors)
        XCTAssertEqual(document.failureReasons, [])
        XCTAssertNil(document.progress)
    }

    func testDecodesRuntimeStatusV2Progress() throws {
        let document = try decodeFixture(RuntimeStatusDocument.self, named: "runtime-status-v2-updating")

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.status, .updating)
        XCTAssertEqual(document.progress?.operation, .applyBundle)
        XCTAssertEqual(document.progress?.step, .activateGuestUpdate)
        XCTAssertEqual(document.progress?.stepStatus, .started)
        XCTAssertEqual(document.progress?.reasonCodes, ["guest-activation-pending"])
    }

    func testRuntimeServiceOperationsRoundTrip() throws {
        XCTAssertEqual(RuntimeOperation(rawValue: "start-services"), .startServices)
        XCTAssertEqual(RuntimeOperation.startServices.rawValue, "start-services")
        XCTAssertEqual(RuntimeOperation(rawValue: "stop-services"), .stopServices)
        XCTAssertEqual(RuntimeOperation.stopServices.rawValue, "stop-services")
        XCTAssertEqual(RuntimeOperation(rawValue: "repair-services"), .repairServices)
        XCTAssertEqual(RuntimeOperation.repairServices.rawValue, "repair-services")
        XCTAssertEqual(RuntimeOperation(rawValue: "prepare-update-shutdown"), .prepareUpdateShutdown)
        XCTAssertEqual(RuntimeOperation.prepareUpdateShutdown.rawValue, "prepare-update-shutdown")
    }

    func testDecodesGuestRuntimeState() throws {
        let document = try decodeFixture(GuestRuntimeStateDocument.self, named: "runtime-state-ready")

        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.bootID, "7b6a6afd-64f8-4dd5-91f1-6dcbf58f8f7d")
        XCTAssertEqual(document.memory?.percent, 25.0)
        XCTAssertEqual(document.systemDisk?.percent, 31.25)
        XCTAssertEqual(document.vitalFilesDisk?.percent, 25.0)
        XCTAssertEqual(
            document.capabilities,
            GuestRuntimeCapabilities(
                prepareUpdateShutdown: true,
                activateUpdate: true,
                redisBackup: true,
                repairDatastore: true
            )
        )
    }

    func testDecodesGuestRuntimeStateContainerServices() throws {
        let json = """
        {
          "schemaVersion": 1,
          "vmIP": "192.168.64.2",
          "guestHTTP": "200",
          "redisUIHTTP": "200",
          "swaggerUIHTTP": "200",
          "updatedAt": "2026-05-24T00:00:00Z",
          "containerServices": [
            {
              "service": "audit-proxy",
              "name": "vitalserver-audit-proxy-1",
              "state": "running",
              "health": "healthy",
              "exitCode": 0
            }
          ]
        }
        """
        let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.containerServices, [
            RuntimeContainerServiceObservation(
                service: "audit-proxy",
                name: "vitalserver-audit-proxy-1",
                state: "running",
                health: "healthy",
                exitCode: 0
            ),
        ])
    }

    func testDecodesActivationResultV1() throws {
        let document = try decodeFixture(
            GuestUpdateActivationResultDocument.self,
            named: "activate-update-result-v1-completed"
        )

        XCTAssertNil(document.schemaVersion)
        XCTAssertTrue(document.completed)
        XCTAssertFalse(document.failed)
        XCTAssertEqual(document.status, .completed)
    }

    func testDecodesActivationResultV2() throws {
        let document = try decodeFixture(
            GuestUpdateActivationResultDocument.self,
            named: "activate-update-result-v2-running"
        )

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.requestId, "4A3D7063-5E81-4BA1-9E74-74E44347F6E5")
        XCTAssertEqual(document.operation, .activateGuestUpdate)
        XCTAssertEqual(document.step, "load-docker-images")
        XCTAssertFalse(document.completed)
        XCTAssertFalse(document.failed)
    }

    func testDecodesDatastoreRepairResultV2() throws {
        let json = """
        {
          "schemaVersion": 2,
          "requestId": "repair-1",
          "operation": "repair-datastore",
          "status": "running",
          "message": "Datastore repair is running.",
          "updatedAt": "2026-05-21T12:33:57Z"
        }
        """
        let document = try JSONDecoder().decode(DatastoreRepairResultDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.requestId, "repair-1")
        XCTAssertEqual(document.operation, .repairDatastore)
        XCTAssertEqual(document.status, .running)
        XCTAssertFalse(document.completed)
        XCTAssertFalse(document.failed)
    }

    func testUnknownEnumValuesRoundTrip() throws {
        let json = """
        {
          "schemaVersion": 2,
          "product": "TiroshVitalServer",
          "status": "paused",
          "operation": "future-operation",
          "message": "future state",
          "updatedAt": "2026-05-21T12:33:57Z",
          "productRoot": "/Library/Application Support/TiroshVitalServer",
          "runtimeHome": "/Library/Application Support/TiroshVitalServer/vm",
          "runtimeVersion": "0.1.4",
          "vmService": "loaded",
          "proxyService": "loaded",
          "watchdogService": "loaded",
          "vmState": "hibernating",
          "vmErrors": ["vm-runtime-state-stale", "vm-service-state-paused"],
          "vmIP": null,
          "proxyPort": 80,
          "hostProxyHTTP": "failed",
          "guestHTTP": "failed",
          "redisUIHTTP": null,
          "swaggerUIHTTP": null,
          "rootfsBase": "present",
          "vmDisk": "present",
          "failureReasons": [],
          "latestBackup": null,
          "progress": {
            "operation": "future-operation",
            "phase": "future-phase",
            "step": "future-step",
            "stepStatus": "future-step-status",
            "message": "future progress",
            "reasonCodes": [],
            "startedAt": null,
            "updatedAt": "2026-05-21T12:33:57Z"
          }
        }
        """
        let document = try JSONDecoder().decode(RuntimeStatusDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.status.rawValue, "paused")
        XCTAssertEqual(document.operation.rawValue, "future-operation")
        XCTAssertEqual(document.vmService, .loaded)
        XCTAssertEqual(document.vmState?.rawValue, "hibernating")
        XCTAssertEqual(document.vmErrors ?? [], [.runtimeStateStale, .serviceNotLoaded("paused")])
        XCTAssertEqual(document.rootfsBase, .present)
        XCTAssertEqual(document.progress?.phase.rawValue, "future-phase")
        XCTAssertEqual(document.progress?.stepStatus?.rawValue, "future-step-status")

        let encoded = try JSONEncoder().encode(document)
        let roundTripped = try JSONDecoder().decode(RuntimeStatusDocument.self, from: encoded)
        XCTAssertEqual(roundTripped.status.rawValue, "paused")
        XCTAssertEqual(roundTripped.vmService.rawValue, "loaded")
        XCTAssertEqual(roundTripped.vmState?.rawValue, "hibernating")
        XCTAssertEqual(roundTripped.vmErrors ?? [], [.runtimeStateStale, .serviceNotLoaded("paused")])
        XCTAssertEqual(roundTripped.rootfsBase.rawValue, "present")
        XCTAssertEqual(roundTripped.progress?.phase.rawValue, "future-phase")
    }

    func testRuntimeVMStateDefinesObservedStatesAndPreservesUnknownValues() throws {
        let states: [RuntimeVMState] = [
            .notInstalled,
            .stopped,
            .starting,
            .running,
            .stale,
            .unreachable,
            .failed,
        ]

        XCTAssertEqual(states.map(\.rawValue), [
            "not-installed",
            "stopped",
            "starting",
            "running",
            "stale",
            "unreachable",
            "failed",
        ])

        let encoded = try JSONEncoder().encode(RuntimeVMState.unknown("hibernating"))
        let decoded = try JSONDecoder().decode(RuntimeVMState.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("hibernating"))
    }

    func testRuntimeVMErrorDefinesObservedErrorsAndPreservesUnknownValues() throws {
        let errors: [RuntimeVMError] = [
            .missingExecutable,
            .missingRootfsBase,
            .missingDisk,
            .serviceNotLoaded("not loaded"),
            .missingIPAddress,
            .runtimeStateMissing,
            .runtimeStateStale,
            .launchFailed("virtualization"),
            .invalidConfiguration("network"),
            .hostResourceUnavailable("memory"),
            .diskAttachmentInvalid,
            .guestFilesystemError,
            .guestFilesystemReadOnly,
            .guestDiskIO,
            .guestHTTP("failed"),
            .guestBootstrapMissingRuntimePackages,
            .guestBootstrapFailed,
        ]

        XCTAssertEqual(errors.map(\.rawValue), [
            "vm-missing-executable",
            "vm-missing-rootfs-base",
            "vm-missing-disk",
            "vm-service-state-not loaded",
            "vm-missing-ip-address",
            "vm-runtime-state-missing",
            "vm-runtime-state-stale",
            "vm-launch-failed-virtualization",
            "vm-invalid-configuration-network",
            "vm-host-resource-unavailable-memory",
            "vm-disk-attachment-invalid",
            "vm-guest-filesystem-error",
            "vm-guest-filesystem-read-only",
            "vm-guest-disk-io-error",
            "vm-guest-http-failed",
            "vm-guest-bootstrap-missing-runtime-packages",
            "vm-guest-bootstrap-failed",
        ])

        let encoded = try JSONEncoder().encode(RuntimeVMError.unknown("vm-future-error"))
        let decoded = try JSONDecoder().decode(RuntimeVMError.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("vm-future-error"))
    }

    func testRuntimeVMErrorDefinesCategoryAndRecoveryAction() {
        XCTAssertEqual(RuntimeVMError.diskAttachmentInvalid.category, .guestStorage)
        XCTAssertEqual(RuntimeVMError.diskAttachmentInvalid.recoveryAction, .backupAndRecreateVM)
        XCTAssertTrue(RuntimeVMError.diskAttachmentInvalid.requiresDataPreservationBeforeRecovery)

        XCTAssertEqual(RuntimeVMError.runtimeStateMissing.category, .guestAgent)
        XCTAssertEqual(RuntimeVMError.runtimeStateMissing.recoveryAction, .restartGuestAgent)
        XCTAssertFalse(RuntimeVMError.runtimeStateMissing.requiresDataPreservationBeforeRecovery)
    }

    func testRuntimeFailureReasonsDecodeAsTypedCodes() throws {
        let json = """
        [
          "missing-vm-bin",
          "vm-service-not loaded",
          "host-proxy-http-502",
          "audit-proxy-http-failed",
          "container-service-app-state-unhealthy",
          "vitaldb-anomaly-duplicate-ip-subject-10.0.0.10",
          "proxy-port-80-in-use-by-nginx-1234",
          "host-proxy-listener-scan-failed-port-80-exit-1",
          "guest-bootstrap-missing-runtime-packages",
          "future-reason"
        ]
        """
        let reasons = try JSONDecoder().decode([RuntimeFailureReason].self, from: Data(json.utf8))

        XCTAssertEqual(reasons[0], .missingVMBin)
        XCTAssertEqual(reasons[1], .vmService("not loaded"))
        XCTAssertEqual(reasons[2], .hostProxyHTTP("502"))
        XCTAssertEqual(reasons[3], .auditProxyHTTP("failed"))
        XCTAssertEqual(reasons[4], .containerService(service: "app", state: "unhealthy"))
        XCTAssertEqual(reasons[5], .vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10"))
        XCTAssertEqual(reasons[6], .proxyPortInUse(port: 80, listeners: "nginx-1234"))
        XCTAssertEqual(reasons[7], .hostProxyListenerScanFailed(port: 80, exitCode: 1))
        XCTAssertEqual(reasons[8], .guestBootstrapMissingRuntimePackages)
        XCTAssertEqual(reasons[9], .unknown("future-reason"))

        let encoded = try JSONEncoder().encode(reasons)
        let roundTripped = try JSONDecoder().decode([RuntimeFailureReason].self, from: encoded)
        XCTAssertEqual(roundTripped.map(\.rawValue), [
            "missing-vm-bin",
            "vm-service-not loaded",
            "host-proxy-http-502",
            "audit-proxy-http-failed",
            "container-service-app-state-unhealthy",
            "vitaldb-anomaly-duplicate-ip-subject-10.0.0.10",
            "proxy-port-80-in-use-by-nginx-1234",
            "host-proxy-listener-scan-failed-port-80-exit-1",
            "guest-bootstrap-missing-runtime-packages",
            "future-reason",
        ])
    }

    func testRuntimeFailureReasonsDefineDomainClassificationAndRecovery() {
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").recoveryAction, .freeProxyPort)
        XCTAssertEqual(RuntimeFailureReason.proxyPortInUse(port: 80, listeners: "nginx-1234").domainSeverity, .critical)

        XCTAssertEqual(RuntimeFailureReason.auditProxyHTTP("failed").domainCategory, .container)
        XCTAssertEqual(RuntimeFailureReason.auditProxyHTTP("failed").recoveryAction, .restartContainerServices)

        XCTAssertEqual(RuntimeFailureReason.vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10").domainCategory, .vitalDB)
        XCTAssertEqual(RuntimeFailureReason.vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10").domainSeverity, .warning)
        XCTAssertEqual(
            RuntimeFailureReason.vitalDBAnomaly(kind: "duplicate-ip", subject: "10.0.0.10").recoveryAction,
            .inspectVitalDBObservation
        )

        XCTAssertEqual(RuntimeFailureReason.vitalDBAnomaly(kind: "observer-unhealthy", subject: "vitaldb").domainCategory, .vitalDB)
        XCTAssertEqual(
            RuntimeFailureReason.vitalDBAnomaly(kind: "observer-unhealthy", subject: "vitaldb").recoveryAction,
            .inspectVitalDBObservation
        )

        XCTAssertEqual(RuntimeFailureReason.unknown("vm-disk-attachment-invalid").domainCategory, .guestStorage)
        XCTAssertEqual(RuntimeFailureReason.unknown("vm-disk-attachment-invalid").recoveryAction, .backupAndRecreateVM)
        XCTAssertTrue(RuntimeFailureReason.unknown("vm-disk-attachment-invalid").requiresDataPreservationBeforeRecovery)

        XCTAssertEqual(RuntimeFailureReason.redisUIHTTP("failed").domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.redisUIHTTP("failed").recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.runtimeStatusDocumentInvalid.domainCategory, .observability)
        XCTAssertEqual(RuntimeFailureReason.runtimeStatusDocumentInvalid.domainSeverity, .critical)
        XCTAssertEqual(RuntimeFailureReason.runtimeStatusDocumentInvalid.recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.launchdServiceCrashed(service: "vm", exitCode: 78).domainCategory, .vmLifecycle)
        XCTAssertEqual(RuntimeFailureReason.launchdServiceCrashed(service: "vm", exitCode: 78).recoveryAction, .restartVMService)

        XCTAssertEqual(RuntimeFailureReason.hostProxyConfigInvalid.domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.hostProxyConfigInvalid.recoveryAction, .repairProxyConfiguration)

        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanFailed(port: 80, exitCode: 1).domainCategory, .hostProxy)
        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanFailed(port: 80, exitCode: 1).domainSeverity, .warning)
        XCTAssertEqual(RuntimeFailureReason.hostProxyListenerScanFailed(port: 80, exitCode: 1).recoveryAction, .inspectLogs)

        XCTAssertEqual(RuntimeFailureReason.containerRestartLoop(service: "redis").domainCategory, .container)
        XCTAssertEqual(RuntimeFailureReason.containerRestartLoop(service: "redis").recoveryAction, .restartContainerServices)

        XCTAssertEqual(RuntimeFailureReason.vitalDBObservationStale.domainSeverity, .warning)
    }

    func testRuntimeDomainErrorDocumentOwnsCodeCategorySeverityAndRecoveryAction() throws {
        let error = RuntimeDomainError(.guestBootstrapFailed)

        XCTAssertEqual(error.code, .guestBootstrapFailed)
        XCTAssertEqual(error.category, .guestBootstrap)
        XCTAssertEqual(error.severity, .critical)
        XCTAssertEqual(error.recoveryAction, .repairGuestBootstrap)

        let encoded = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(RuntimeDomainError.self, from: encoded)
        XCTAssertEqual(decoded, error)
    }

    func testRuntimeEventTypeDefinesOperationalTaxonomyAndPreservesUnknownValues() throws {
        let knownTypes: [RuntimeEventType] = [
            .statusChanged,
            .progressUpdated,
            .healthObserved,
            .recoveryTriggered,
            .recoveryCompleted,
            .recoverySuppressed,
            .domainErrorObserved,
            .vmErrorObserved,
            .containerObserved,
            .auditProxyObserved,
            .vitalDBObserved,
            .vitalDBObserverUnhealthy,
            .vitalDBAnomalyDetected,
            .watchdogSkipped,
            .recoveryPlanned,
            .serviceRestartDispatched,
            .observabilityStoreFailed,
            .runtimeStatusObserved,
            .guestStateObserved,
            .runtimeCommandStarted,
            .runtimeCommandCompleted,
            .runtimeCommandFailed,
        ]

        XCTAssertEqual(knownTypes.map(\.rawValue), [
            "status-changed",
            "progress-updated",
            "health-observed",
            "recovery-triggered",
            "recovery-completed",
            "recovery-suppressed",
            "domain-error-observed",
            "vm-error-observed",
            "container-observed",
            "audit-proxy-observed",
            "vitaldb-observed",
            "vitaldb-observer-unhealthy",
            "vitaldb-anomaly-detected",
            "watchdog-skipped",
            "recovery-planned",
            "service-restart-dispatched",
            "observability-store-failed",
            "runtime-status-observed",
            "guest-state-observed",
            "runtime-command-started",
            "runtime-command-completed",
            "runtime-command-failed",
        ])

        let encoded = try JSONEncoder().encode(RuntimeEventType.unknown("vendor-event"))
        let decoded = try JSONDecoder().decode(RuntimeEventType.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("vendor-event"))
    }

    func testRuntimeEventQueryClampsLimitAndPreservesCursor() {
        let cursor = RuntimeEventCursor(timestamp: "2026-05-24T00:01:00Z", id: "event-2")

        XCTAssertEqual(RuntimeEventQuery(limit: 0).limit, 1)
        XCTAssertEqual(RuntimeEventQuery(limit: 1_000).limit, RuntimeEventQuery.maximumLimit)

        let query = RuntimeEventQuery(
            limit: 25,
            eventType: .auditProxyObserved,
            since: "2026-05-24T00:00:00Z",
            before: cursor
        )

        XCTAssertEqual(query.limit, 25)
        XCTAssertEqual(query.eventType, .auditProxyObserved)
        XCTAssertEqual(query.since, "2026-05-24T00:00:00Z")
        XCTAssertEqual(query.before, cursor)
    }

    func testRuntimeEventDocumentAllowsEventsWithoutRuntimeStatusContext() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "event-1",
          "source": "host-command",
          "eventType": "runtime-command-started",
          "timestamp": "2026-05-30T01:00:00Z",
          "product": "com.tirosh.vitalserver",
          "message": "command started",
          "runtimeVersion": "0.1.9",
          "failureReasons": []
        }
        """

        let event = try JSONDecoder().decode(RuntimeEventDocument.self, from: Data(json.utf8))

        XCTAssertNil(event.status)
        XCTAssertNil(event.operation)
        XCTAssertEqual(event.source, "host-command")
        XCTAssertEqual(event.eventType, .runtimeCommandStarted)

        let roundTripped = try JSONDecoder().decode(RuntimeEventDocument.self, from: try JSONEncoder().encode(event))
        XCTAssertNil(roundTripped.status)
        XCTAssertNil(roundTripped.operation)
    }

    private func decodeFixture<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
