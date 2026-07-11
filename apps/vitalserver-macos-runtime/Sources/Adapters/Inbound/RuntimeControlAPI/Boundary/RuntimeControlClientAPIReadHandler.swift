import Foundation
import RuntimeControl
import Contracts
import Errors

@MainActor
public struct RuntimeControlClientAPIReadHandler: RuntimeControlAPIReadHandler {
    private let client: any RuntimeControlClient
    private let hostClient: (any RuntimeHostClient)?

    public init(client: any RuntimeControlClient, hostClient: (any RuntimeHostClient)? = nil) {
        self.client = client
        self.hostClient = hostClient
    }

    public func loadPlatformCapabilities() async throws -> PlatformCapabilities {
        PlatformCapabilities(client.capabilities)
    }

    public func loadRuntimeCapabilities() async throws -> RuntimeCapabilities {
        try await client.runtimeCapabilities()
    }

    public func loadPlatformState() async throws -> PlatformState {
        let settings = client.loadSettings()
        return client.loadPlatformState(settings: settings)
    }

    public func loadOperationState() async throws -> PlatformOperationState {
        client.loadOperationState()
    }

    public func loadRuntimeOperationEvents(
        query: RuntimeEventQuery
    ) async throws -> RuntimeOperationEventHistory {
        try await client.loadRuntimeOperationEvents(query: query)
    }

    public func loadVitalDBObservationSnapshot() async throws -> RuntimeVitalDBObservationSnapshot {
        client.loadVitalDBObservationSnapshot()
    }

    public func loadVitalDBRecorders() async throws -> RuntimeVitalRecorderHistory {
        client.loadVitalDBRecorders()
    }

    public func loadVitalDBBeds() async throws -> RuntimeVitalBedHistory {
        client.loadVitalDBBeds()
    }

    public func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async throws -> RuntimeVitalRecorderActivityWindow {
        client.loadVitalDBRecorderActivityWindow(query: query)
    }

    public func loadVitalDBRelationships() async throws -> RuntimeVitalRelationshipHistory {
        client.loadVitalDBRelationships()
    }

    public func loadRedisRelayStatus() async throws -> RuntimeRedisRelayStatusReadResult {
        try await client.loadRedisRelayStatus()
    }

    public func loadHealthStatus() async throws -> PlatformState {
        let settings = client.loadSettings()
        return await client.loadHealthStatus(settings: settings)
    }

    public func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead {
        try await client.loadRuntimeProductSettings()
    }

    public func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        try await client.loadReleaseInfo()
    }

    public func loadInstallInfo() async throws -> RuntimeInstallInfo {
        client.loadInstallInfo()
    }

    public func loadLabScenarios() async throws -> RuntimeLabScenarioList {
        try await client.loadLabScenarios()
    }

    public func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        try await client.loadLabVitalFiles()
    }

    public func loadLabBeds() async throws -> RuntimeLabBedList {
        try await client.loadLabBeds()
    }

    public func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        try await client.loadLabRecorders()
    }

    public func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        try await client.createLabBeds(request)
    }

    public func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        try await client.deleteLabBeds(request)
    }

    public func resetLabBeds() async throws -> RuntimeLabBedList {
        try await client.resetLabBeds()
    }

    public func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        try await client.createLabRecorders(request)
    }

    public func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        try await client.deleteLabRecorders(request)
    }

    public func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        try await client.resetLabRecorders()
    }

    public func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await client.hideVitalDBRecorders(request)
    }

    public func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await client.unhideVitalDBRecorders(request)
    }

    public func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await client.deleteVitalDBRecorders(request)
    }

    public func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        try await client.hideVitalDBBeds(request)
    }

    public func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        try await client.unhideVitalDBBeds(request)
    }

    public func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        try await client.deleteVitalDBBeds(request)
    }

    public func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse {
        try await client.createLabSession(request)
    }

    public func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await client.loadLabSession(sessionId: sessionId)
    }

    public func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await client.startLabSession(sessionId: sessionId)
    }

    public func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await client.stopLabSession(sessionId: sessionId)
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        try await client.replayLabVitalFile(request)
    }

    public func uploadLabVitalFile(_ request: RuntimeLabVitalFileUploadRequest) async throws -> RuntimeLabVitalFileUploadResponse {
        try await client.uploadLabVitalFile(request)
    }

    public func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        try await client.guestStackStatus()
    }

    public func listGuestServices() async throws -> RuntimeGuestControlServiceList {
        try await client.listGuestServices()
    }

    public func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        try await client.guestServiceStatus(service)
    }

    public func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        try await client.guestServiceResource(service)
    }

    public func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        let textResult = await hostClient.loadLogTextResult(
            sourceID: request.source,
            lineLimit: request.lineLimit
        )
        return RuntimeLogTextResponse(
            text: RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.noLogData)
                .displayText(textResult)
        )
    }

    public func loadBackups() async throws -> [RuntimeBackup] {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        let settings = client.loadSettings()
        let status = client.loadPlatformState(settings: settings)
        return try hostClient.loadBackups(latestBackupPath: status.latestBackup)
    }

    public func loadRedisBackups() async throws -> [RuntimeBackup] {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return try hostClient.loadRedisBackups()
    }

    public func loadRuntimeDataBackups() async throws -> [RuntimeBackup] {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return try hostClient.loadRuntimeDataBackups()
    }

    public func applyRuntimeProductSettings(
        _ settings: GuestRuntimeSettingsDocument
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await client.applyRuntimeProductSettings(settings)
    }

    public func applyRuntimeAdminPassword(
        _ password: String
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await client.applyRuntimeAdminPassword(password)
    }

    public func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead {
        try await client.loadRuntimeRedisRelaySettings()
    }

    public func applyRuntimeRedisRelaySettings(
        _ settings: RuntimeRedisRelaySettingsApplyRequest
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await client.applyRuntimeRedisRelaySettings(settings)
    }

    public func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await client.startGuestService(request)
    }

    public func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await client.stopGuestService(request)
    }

    public func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await client.restartGuestService(request)
    }

    public func repairRuntimeServices() async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.repairRuntimeServices())
    }

    public func repairProxy() async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.repairProxy())
    }

    public func repairDatastore() async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.repairDatastore())
    }

    public func repairVMDisk() async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.repairVMDisk())
    }

    public func createRedisBackup() async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.createRedisBackup())
    }

    public func createRuntimeDataBackup() async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.createRuntimeDataBackup())
    }

    public func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        let summary = hostClient.updateBundleSummaryResult(url: try localFileURL(bundle))
        return RuntimeUpdateBundleSummaryResponse(
            summary: RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.notReported)
                .displayText(summary)
        )
    }

    public func verifyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.verifyUpdateBundle(url: try localFileURL(bundle)))
    }

    public func applyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.applyUpdateBundle(url: try localFileURL(bundle)))
    }

    public func rollbackBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.rollbackRuntime(backupURL: try localFileURL(backup)))
    }

    public func restoreRedisBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.restoreRedisBackup(backupURL: try localFileURL(backup)))
    }

    public func restoreRuntimeDataBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.restoreRuntimeDataBackup(backupURL: try localFileURL(backup)))
    }

    public func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.deleteBackup(url: try localFileURL(backup)))
    }

    public func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return try await hostClient.exportLogs(to: try localFileURL(destination))
    }

    public func createPlatformSupportExport() async throws -> PlatformWorkflowOperation {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        let directory = URL(fileURLWithPath: "/Library/Application Support/VitalServerHelper/support", isDirectory: true)
        return await createManagedPlatformSupportExport(in: directory) { destination in
            try await hostClient.exportLogs(to: destination)
        }
    }

    public func acquireOperationLease(
        _ request: RuntimeOperationLeaseAcquireRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return try await hostClient.acquireOperationLease(request.document)
    }

    public func heartbeatOperationLease(
        _ request: RuntimeOperationLeaseHeartbeatRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return try await hostClient.heartbeatOperationLease(
            operationId: request.operationId,
            heartbeatAt: request.heartbeatAt,
            expiresAt: request.expiresAt
        )
    }

    public func releaseOperationLease(
        _ request: RuntimeOperationLeaseReleaseRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.platformAffordanceUnavailable
        }
        return try await hostClient.releaseOperationLease(operationId: request.operationId)
    }

    public func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.uninstallRuntime(mode: mode))
    }

    private func localFileURL(_ reference: RuntimeControlFileReference) throws -> URL {
        guard reference.kind == .localPath else {
            throw RuntimeControlAPIReadHandlerError.unsupportedFileReference(reference.kind.rawValue)
        }
        return URL(fileURLWithPath: reference.value)
    }
}
