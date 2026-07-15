@testable import MacControlPanelHost
@testable import MacPlatformAgent
import Application
import Contracts
import Foundation
import RuntimeControl
import XCTest
import Errors
@testable import InboundAdapters
@testable import OutboundAdapters

final class RuntimeSectionTests: XCTestCase {
    func testStableRuntimeSectionsShowProductLab() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: false).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionRecorders,
            AppConstants.Labels.sectionBeds,
            AppConstants.Labels.sectionLab,
            AppConstants.Labels.sectionObservability,
            AppConstants.Labels.sectionLog,
            AppConstants.Labels.sectionSettings,
            AppConstants.Labels.sectionUpdate,
            AppConstants.Labels.sectionInfo,
            AppConstants.Labels.sectionAdvanced,
            AppConstants.Labels.sectionDangerZone,
        ])
    }

    func testTestEnabledRuntimeSectionsKeepSameProductNavigation() {
        XCTAssertEqual(RuntimeSection.visibleSections(testEnabled: true).map(\.title), [
            AppConstants.Labels.sectionStatus,
            AppConstants.Labels.sectionRecorders,
            AppConstants.Labels.sectionBeds,
            AppConstants.Labels.sectionLab,
            AppConstants.Labels.sectionObservability,
            AppConstants.Labels.sectionLog,
            AppConstants.Labels.sectionSettings,
            AppConstants.Labels.sectionUpdate,
            AppConstants.Labels.sectionInfo,
            AppConstants.Labels.sectionAdvanced,
            AppConstants.Labels.sectionDangerZone,
        ])
    }

    func testRuntimeSectionsExposePrimaryUtilityAndOverflowGroups() {
        XCTAssertEqual(RuntimeSection.primarySections(testEnabled: true), [
            .status,
            .recorders,
            .beds,
            .lab,
            .settings,
            .update,
        ])
        XCTAssertEqual(RuntimeSection.utilitySections(testEnabled: true), [.advanced])
        XCTAssertEqual(RuntimeSection.overflowSections(testEnabled: true), [.observability, .log, .info, .dangerZone])
    }

    func testStableRuntimeSectionOverflowMovesDiagnosticsOutOfPrimaryNavigation() {
        XCTAssertEqual(RuntimeSection.overflowSections(testEnabled: false), [.observability, .log, .info, .dangerZone])
        XCTAssertTrue(RuntimeSection.sectionIsInOverflow(.dangerZone, testEnabled: false))
        XCTAssertFalse(RuntimeSection.sectionIsInOverflow(.advanced, testEnabled: false))
    }

    func testRecoverySectionsRefreshBackupListsWhileSelected() {
        XCTAssertTrue(RuntimeSection.advanced.refreshesBackupListsWhileSelected)
        XCTAssertTrue(RuntimeSection.dangerZone.refreshesBackupListsWhileSelected)
        XCTAssertFalse(RuntimeSection.status.refreshesBackupListsWhileSelected)
        XCTAssertFalse(RuntimeSection.update.refreshesBackupListsWhileSelected)
    }

    func testAdvancedSectionRefreshesRuntimeProductServicesWhileSelected() {
        XCTAssertTrue(RuntimeSection.advanced.refreshesRuntimeProductServicesWhileSelected)
        XCTAssertTrue(RuntimeSection.status.refreshesRuntimeProductServicesWhileSelected)
        XCTAssertFalse(RuntimeSection.dangerZone.refreshesRuntimeProductServicesWhileSelected)
    }

    func testOnlyAdvancedSectionRefreshesRedisRelayWhileSelected() {
        XCTAssertTrue(RuntimeSection.advanced.refreshesRedisRelayWhileSelected)
        XCTAssertFalse(RuntimeSection.status.refreshesRedisRelayWhileSelected)
        XCTAssertFalse(RuntimeSection.dangerZone.refreshesRedisRelayWhileSelected)
    }

    @MainActor
    func testRuntimeControlDevConsoleURLUsesLocalAPI() {
        XCTAssertEqual(
            RuntimeControlLocalAPIConstants.devConsoleURL(port: 18321),
            "http://127.0.0.1:18321/dev/runtime-control"
        )
        XCTAssertEqual(
            RuntimeControlLocalAPIConstants.pwaURL(port: 18321),
            "http://127.0.0.1:18321/"
        )
    }

    @MainActor
    func testRuntimeControlAPIHandlerDelegatesOperationLeaseOwnerMutationsToOperationLeaseClient() async throws {
        let client = HostFakeRuntimeControlClient()
        let handler = makeRuntimeControlAPIHandler(client: client)
        let lease = RuntimeOperationLeaseDocument(
            operationId: "operation-1",
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-09T00:00:00Z",
            heartbeatAt: "2026-07-09T00:00:00Z",
            expiresAt: "2026-07-09T00:05:00Z",
            message: "applying bundle"
        )

        let acquire = try await handler.acquireOperationLease(.init(document: lease))
        let heartbeat = try await handler.heartbeatOperationLease(.init(
            operationId: lease.operationId,
            heartbeatAt: "2026-07-09T00:01:00Z",
            expiresAt: "2026-07-09T00:06:00Z"
        ))
        let release = try await handler.releaseOperationLease(.init(operationId: lease.operationId))

        XCTAssertEqual(acquire, RuntimeOperationLeaseMutationResponse(operationId: lease.operationId, state: .acquired))
        XCTAssertEqual(heartbeat, RuntimeOperationLeaseMutationResponse(operationId: lease.operationId, state: .heartbeatRecorded))
        XCTAssertEqual(release, RuntimeOperationLeaseMutationResponse(operationId: lease.operationId, state: .released))
        XCTAssertEqual(client.acquiredOperationLeases, [lease])
        XCTAssertEqual(client.heartbeatOperationLeaseRequests.map(\.operationId), [lease.operationId])
        XCTAssertEqual(client.releasedOperationLeaseIDs, [lease.operationId])
    }

    @MainActor
    func testRuntimeControlAPIHandlerPreservesGuestDatastoreRepairOperation() async throws {
        let client = HostFakeRuntimeControlClient()
        let failure = RuntimeGuestControlOperationFailure(
            kind: "datastore-repair-failed",
            message: "redis append-only file repair failed"
        )
        client.datastoreRepairOperation = RuntimeGuestControlServiceOperation(
            operationId: "datastore-repair-1",
            service: "datastore-repair",
            command: .repairDatastore,
            state: .failed,
            createdAt: "2026-07-01T00:00:00Z",
            updatedAt: "2026-07-01T00:00:01Z",
            failure: failure
        )
        let handler = makeRuntimeControlAPIHandler(client: client)

        let operation = try await handler.repairDatastore()

        XCTAssertEqual(operation.state, .failed)
        XCTAssertEqual(operation.failure, failure)
    }

    @MainActor
    func testRuntimeProviderControlMapsUnavailablePreflightToNotImplemented() async throws {
        let client = HostFakeRuntimeControlClient()
        client.runtimeProviderControlError = RuntimeClientError.missingLauncher
        let router = RuntimeControlAPIRouter(handler: makeRuntimeControlAPIHandler(client: client))

        let response = await router.route(.init(
            method: .post,
            path: "/platform/runtime-provider/restart"
        ))

        XCTAssertEqual(response.status, .notImplemented)
        let error = try JSONDecoder().decode(
            RuntimeControlErrorResponse.self,
            from: try XCTUnwrap(response.body)
        )
        XCTAssertEqual(error.code, .platformAffordanceUnavailable)
        XCTAssertTrue(error.message.contains("launcher is missing"))
    }

    @MainActor
    func testRuntimeProviderControlMapsInspectionPreflightFailureToTypedServiceUnavailable() async throws {
        let client = HostFakeRuntimeControlClient()
        client.runtimeProviderControlError = RuntimeClientError.launcherInspectionFailed(
            path: "/Library/Application Support/VitalServerHelper/vitalserver-vm",
            reason: "permission denied"
        )
        let router = RuntimeControlAPIRouter(handler: makeRuntimeControlAPIHandler(client: client))

        let response = await router.route(.init(
            method: .post,
            path: "/platform/runtime-provider/restart"
        ))

        XCTAssertEqual(response.status, .serviceUnavailable)
        let command = try JSONDecoder().decode(
            RuntimeProviderCommandResponse.self,
            from: try XCTUnwrap(response.body)
        )
        XCTAssertEqual(command.state, .failed)
        XCTAssertEqual(command.failure?.kind, "runtime-provider-control-preflight-failed")
        XCTAssertTrue(command.failure?.message.contains("permission denied") == true)
    }

    @MainActor
    func testRuntimeProviderControlMapsEffectFailureToTypedServiceUnavailableWithStderr() async throws {
        let client = HostFakeRuntimeControlClient()
        client.runtimeProviderControlResult = RuntimeCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "launchd access denied"
        )
        client.vmLifecycleResource = .missing(readError: "lifecycle document missing")
        let router = RuntimeControlAPIRouter(handler: makeRuntimeControlAPIHandler(client: client))

        let response = await router.route(.init(
            method: .post,
            path: "/platform/runtime-provider/restart"
        ))

        XCTAssertEqual(response.status, .serviceUnavailable)
        let command = try JSONDecoder().decode(
            RuntimeProviderCommandResponse.self,
            from: try XCTUnwrap(response.body)
        )
        XCTAssertEqual(command.state, .failed)
        XCTAssertEqual(command.provider, client.vmLifecycleResource)
        XCTAssertEqual(command.failure?.kind, "runtime-provider-control-failed")
        XCTAssertTrue(command.failure?.message.contains("stderr=launchd access denied") == true)
    }

    @MainActor
    func testControlPanelDoesNotOwnPlatformAPIServer() {
        XCTAssertFalse(MacRuntimeControlEnvironment.shouldStartRuntimeControlAPIServer())
        XCTAssertFalse(MacRuntimeControlEnvironment.shouldServeRuntimeControlDevConsole(testEnabled: false))
        XCTAssertTrue(MacRuntimeControlEnvironment.shouldServeRuntimeControlDevConsole(testEnabled: true))
    }

    @MainActor
    func testPlatformAgentPersistsManagedSupportExportWorkflow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = HostFakeRuntimeControlClient()
        client.exportLogData = Data("support evidence".utf8)
        let workflow = root.appendingPathComponent("run/platform-workflow.json")
        let handler = makeRuntimeControlAPIHandler(
            client: client,
            platformWorkflowDocument: workflow,
            supportDirectory: root.appendingPathComponent("support", isDirectory: true)
        )

        let completed = try await handler.createPlatformSupportExport()
        let resource = try await handler.loadPlatformWorkflow()

        XCTAssertEqual(completed.state, .completed)
        XCTAssertEqual(resource.state, .loaded)
        XCTAssertEqual(resource.operation, completed)
        XCTAssertNotNil(completed.artifact)
    }

    @MainActor
    func testPlatformAgentDelegatesGuestStackAndServiceResourceReads() async throws {
        let client = HostFakeRuntimeControlClient()
        let handler = makeRuntimeControlAPIHandler(client: client)

        let stack = try await handler.guestStackStatus()
        let resource = try await handler.guestServiceResource("recorder-ingress")

        XCTAssertEqual(stack.state, "loaded")
        XCTAssertEqual(resource.service, "recorder-ingress")
        XCTAssertEqual(client.guestStackStatusCount, 1)
        XCTAssertEqual(client.guestServiceResourceRequests, ["recorder-ingress"])
    }

    @MainActor
    private func makeRuntimeControlAPIHandler(
        client: HostFakeRuntimeControlClient,
        platformWorkflowDocument: URL = InstalledRuntimePaths.defaultInstalled.hostRunDirectory.appendingPathComponent("platform-workflow.json"),
        supportDirectory: URL = InstalledRuntimePaths.defaultInstalled.productRoot.appendingPathComponent("support", isDirectory: true)
    ) -> MacRuntimeControlAPIHandler {
        MacRuntimeControlAPIHandler(
            commandClient: client,
            hostClient: client,
            guestMaintenanceClient: client,
            operationLeaseClient: client,
            guestAddressClient: client,
            vmLifecycleClient: client,
            readWorker: MacRuntimeControlReadWorker(
                releaseInfo: RuntimeReleaseInfo(
                    helperVersion: "helper",
                    minimumUpdaterVersion: "1",
                    vitalServerVersion: "runtime",
                    services: []
                ),
                platformStateReader: HostStubStatusReader(),
                observabilityReader: HostStubObservabilityReader(),
                fileReader: HostStubFileReader(),
                settingsReader: HostStubSettingsReader()
            ),
            platformWorkflowDocument: platformWorkflowDocument,
            supportDirectory: supportDirectory
        )
    }
}

@MainActor
private final class HostFakeRuntimeControlClient:
    RuntimeControlClient,
    RuntimeHostClient,
    RuntimeGuestMaintenanceOperationClient,
    RuntimeOperationLeaseMutationClient,
    RuntimeGuestAddressResourceClient,
    RuntimeVMLifecycleResourceClient
{
    var capabilities = RuntimeControlCapabilities(canOpenLocalFiles: false)
    var applySettingsResult = RuntimeCommandResult(exitCode: 0, stdout: "settings applied", stderr: "")
    var acquiredOperationLeases: [RuntimeOperationLeaseDocument] = []
    var heartbeatOperationLeaseRequests: [RuntimeOperationLeaseHeartbeatRequest] = []
    var releasedOperationLeaseIDs: [String] = []
    var guestAddressResource: RuntimeGuestAddressResourceState = .missing()
    var vmLifecycleResource: RuntimeVMLifecycleResourceState = .missing()
    var runtimeProviderControlResult = RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    var runtimeProviderControlError: Error?
    var exportLogData: Data?
    var datastoreRepairOperation = RuntimeGuestControlServiceOperation(
        operationId: "datastore-repair-1",
        service: "datastore-repair",
        command: .repairDatastore,
        state: .completed,
        createdAt: "2026-07-01T00:00:00Z",
        updatedAt: "2026-07-01T00:00:01Z"
    )
    var guestStackStatusCount = 0
    var guestServiceResourceRequests: [String] = []

    func loadSettings() -> RuntimeSettings { RuntimeSettings() }
    func loadPlatformState(settings: RuntimeSettings) -> PlatformState { platformState() }
    func loadOperationState() -> PlatformOperationState {
        PlatformOperationState(activeOperation: nil, install: .unavailable())
    }
    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState { platformState() }
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory { RuntimeEventHistory(events: []) }
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory { RuntimeEventHistory(events: []) }
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        RuntimeVitalDBObservationSnapshot.fromOptional(nil)
    }
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory { RuntimeVitalRecorderHistory(observations: []) }
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory { RuntimeVitalRelationshipHistory() }
    func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "uninstall", stderr: "")
    }
    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeCommandResult { applySettingsResult }
    func repairProxy() async throws -> RuntimeCommandResult { RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "") }
    func requestDatastoreRepair() async throws -> RuntimeGuestControlServiceOperation {
        datastoreRepairOperation
    }
    func repairDatastore() async throws -> RuntimeCommandResult { RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "") }
    func repairVMDisk() async throws -> RuntimeCommandResult { RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "") }
    func repairRuntimeServices() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func controlRuntimeProvider(
        _: RuntimeProviderCommandAction
    ) async throws -> RuntimeCommandResult {
        if let runtimeProviderControlError {
            throw runtimeProviderControlError
        }
        return runtimeProviderControlResult
    }
    func createRedisBackup() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        RuntimeReleaseInfo(helperVersion: "helper", minimumUpdaterVersion: "1", vitalServerVersion: "runtime", services: [])
    }
    func loadInstallInfo() -> RuntimeInstallInfo { RuntimeInstallInfo() }
    func loadBackups(latestBackupPath: String?) throws -> [RuntimeBackup] { [] }
    func loadRedisBackups() throws -> [RuntimeBackup] { [] }
    func loadRuntimeDataBackups() throws -> [RuntimeBackup] { [] }
    func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        guestStackStatusCount += 1
        return RuntimeGuestControlStackStatus(
            state: "loaded",
            observedAt: "2026-07-15T00:00:00Z",
            services: []
        )
    }
    func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        guestServiceResourceRequests.append(service)
        return RuntimeGuestServiceResource(
            service: service,
            spec: RuntimeGuestServiceSpec(state: "configured"),
            status: RuntimeGuestServiceStatusRead(state: "loaded"),
            conditions: []
        )
    }
    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult { .loaded("") }
    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult { .loaded("") }
    func loadLogTextResult(sourceID: RuntimeLogSource, lineLimit: Int) async -> RuntimeHostTextReadResult { .loaded("") }
    func preferredLogsPath() -> String { "/logs" }
    func vitalFileFolders(root: String) throws -> [VitalFilesFolder] { [] }
    func verifyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func applyUpdateBundle(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func rollbackRuntime(backupURL: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func restoreRedisBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func createRuntimeDataBackup() async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func restoreRuntimeDataBackup(backupURL: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func deleteBackup(url: URL) async throws -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        if let exportLogData {
            try exportLogData.write(to: destination, options: .withoutOverwriting)
        }
        return RuntimeLogExportResult(destination: destination)
    }
    func acquireOperationLease(
        _ document: RuntimeOperationLeaseDocument
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        acquiredOperationLeases.append(document)
        return RuntimeOperationLeaseMutationResponse(operationId: document.operationId, state: .acquired)
    }
    func heartbeatOperationLease(
        operationId: String,
        heartbeatAt: String,
        expiresAt: String?
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        heartbeatOperationLeaseRequests.append(RuntimeOperationLeaseHeartbeatRequest(
            operationId: operationId,
            heartbeatAt: heartbeatAt,
            expiresAt: expiresAt
        ))
        return RuntimeOperationLeaseMutationResponse(operationId: operationId, state: .heartbeatRecorded)
    }
    func releaseOperationLease(
        operationId: String
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        releasedOperationLeaseIDs.append(operationId)
        return RuntimeOperationLeaseMutationResponse(operationId: operationId, state: .released)
    }

    func loadGuestAddressResource() async throws -> RuntimeGuestAddressResourceState {
        guestAddressResource
    }

    func putGuestAddressResource(address: String) async throws -> RuntimeGuestAddressResourceState {
        guestAddressResource = .loaded(.loaded(address: address, source: .platformAgent))
        return guestAddressResource
    }

    func loadVMLifecycleResource() async throws -> RuntimeVMLifecycleResourceState {
        vmLifecycleResource
    }

    func putVMLifecycleResource(
        _ document: RuntimeVMLifecycleDocument
    ) async throws -> RuntimeVMLifecycleResourceState {
        vmLifecycleResource = .loaded(document)
        return vmLifecycleResource
    }
}

private struct HostStubSettingsReader: RuntimeSettingsReading {
    func load() -> RuntimeSettings { RuntimeSettings() }
}

private struct HostStubStatusReader: PlatformStateReading {
    func loadPlatformState(settings: RuntimeSettings) -> PlatformState { platformState() }
    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState { platformState() }
}

private struct HostStubObservabilityReader: RuntimeObservabilityReading {
    func loadRuntimeEvents(limit: Int) -> RuntimeEventHistory { RuntimeEventHistory(events: []) }
    func loadRuntimeEvents(query: RuntimeEventQuery) -> RuntimeEventHistory { RuntimeEventHistory(events: []) }
    func loadVitalDBObservationSnapshot() -> RuntimeVitalDBObservationSnapshot {
        RuntimeVitalDBObservationSnapshot.fromOptional(nil)
    }
    func loadVitalDBRecorders() -> RuntimeVitalRecorderHistory { RuntimeVitalRecorderHistory(observations: []) }
    func loadVitalDBRelationships() -> RuntimeVitalRelationshipHistory { RuntimeVitalRelationshipHistory() }
}

private struct HostStubFileReader: RuntimeHostFileReading {
    func backups(latestBackupPath: String?) throws -> [RuntimeBackup] { [] }
    func redisBackups() throws -> [RuntimeBackup] { [] }
    func runtimeDataBackups() throws -> [RuntimeBackup] { [] }
    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult { .loaded("") }
    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult { .loaded("") }
    func preferredLogsPath() -> String { "/logs" }
    func vitalFileFolders(root: String) throws -> [VitalFilesFolder] { [] }
}
