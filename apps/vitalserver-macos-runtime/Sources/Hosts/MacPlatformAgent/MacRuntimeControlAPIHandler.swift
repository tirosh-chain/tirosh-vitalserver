import Foundation
import Contracts
import Application
import InboundAdapters
import OutboundAdapters
import RuntimeControl
import Errors

@MainActor
public protocol RuntimeOperationLeaseMutationClient: AnyObject {
    func acquireOperationLease(_ document: RuntimeOperationLeaseDocument) async throws -> RuntimeOperationLeaseMutationResponse
    func heartbeatOperationLease(
        operationId: String,
        heartbeatAt: String,
        expiresAt: String?
    ) async throws -> RuntimeOperationLeaseMutationResponse
    func releaseOperationLease(operationId: String) async throws -> RuntimeOperationLeaseMutationResponse
}

@MainActor
public protocol RuntimeVMLifecycleResourceClient: AnyObject {
    func loadVMLifecycleResource() async throws -> RuntimeVMLifecycleResourceState
    func putVMLifecycleResource(_ document: RuntimeVMLifecycleDocument) async throws -> RuntimeVMLifecycleResourceState
}

@MainActor
public protocol RuntimeGuestAddressResourceClient: AnyObject {
    func loadGuestAddressResource() async throws -> RuntimeGuestAddressResourceState
    func putGuestAddressResource(address: String) async throws -> RuntimeGuestAddressResourceState
}

@MainActor
public struct MacRuntimeControlAPIHandler: RuntimeControlAPIReadHandler {
    private let commandClient: any RuntimeControlClient
    private let hostClient: any RuntimeHostClient
    private let guestMaintenanceClient: any RuntimeGuestMaintenanceOperationClient
    private let operationLeaseClient: any RuntimeOperationLeaseMutationClient
    private let guestAddressClient: any RuntimeGuestAddressResourceClient
    private let vmLifecycleClient: any RuntimeVMLifecycleResourceClient
    private let readWorker: MacRuntimeControlReadWorker
    private let localAPIStatus: RuntimeControlLocalAPIStatusRead
    private let platformWorkflowDocument: URL
    private let supportDirectory: URL
    private let scheduleHelperRelaunch: @MainActor () -> Void
    private let scheduleHelperTermination: @MainActor () -> Void

    public init(
        commandClient: any RuntimeControlClient,
        hostClient: any RuntimeHostClient,
        guestMaintenanceClient: any RuntimeGuestMaintenanceOperationClient,
        operationLeaseClient: any RuntimeOperationLeaseMutationClient,
        guestAddressClient: any RuntimeGuestAddressResourceClient,
        vmLifecycleClient: any RuntimeVMLifecycleResourceClient,
        readWorker: MacRuntimeControlReadWorker,
        platformWorkflowDocument: URL = InstalledRuntimePaths.defaultInstalled.hostRunDirectory.appendingPathComponent("platform-workflow.json"),
        supportDirectory: URL = InstalledRuntimePaths.defaultInstalled.productRoot.appendingPathComponent("support", isDirectory: true),
        runtimeControlStartedAt: Date = Date(),
        scheduleHelperRelaunch: @escaping @MainActor () -> Void = {},
        scheduleHelperTermination: @escaping @MainActor () -> Void = {}
    ) {
        self.commandClient = commandClient
        self.hostClient = hostClient
        self.guestMaintenanceClient = guestMaintenanceClient
        self.operationLeaseClient = operationLeaseClient
        self.guestAddressClient = guestAddressClient
        self.vmLifecycleClient = vmLifecycleClient
        self.readWorker = readWorker
        self.platformWorkflowDocument = platformWorkflowDocument
        self.supportDirectory = supportDirectory
        self.localAPIStatus = RuntimeControlLocalAPIStatusRead.reachable(
            startedAt: Self.timestamp(runtimeControlStartedAt)
        )
        self.scheduleHelperRelaunch = scheduleHelperRelaunch
        self.scheduleHelperTermination = scheduleHelperTermination
    }

    public func loadPlatformCapabilities() async throws -> PlatformCapabilities {
        PlatformCapabilities(commandClient.capabilities)
    }

    public func loadRuntimeCapabilities() async throws -> RuntimeCapabilities {
        try await commandClient.runtimeCapabilities()
    }

    public func loadPlatformState() async throws -> PlatformState {
        let settings = await readWorker.loadSettings()
        let status = await readWorker.loadPlatformState(settings: settings)
        return RuntimeControlLocalAPIStatusAssembler.applyingLocalAPIStatus(
            to: status,
            read: localAPIStatus
        )
    }

    public func loadOperationState() async throws -> PlatformOperationState {
        await readWorker.loadOperationState()
    }

    public func loadPlatformWorkflow() async throws -> PlatformWorkflowResource {
        do {
            let data = try Data(contentsOf: platformWorkflowDocument)
            let operation = try JSONDecoder().decode(PlatformWorkflowOperation.self, from: data)
            return PlatformWorkflowResource(state: .loaded, operation: operation, readError: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return PlatformWorkflowResource(
                state: .missing,
                operation: nil,
                readError: "Platform workflow owner is missing path=\(platformWorkflowDocument.path)"
            )
        } catch {
            return PlatformWorkflowResource(
                state: .failed,
                operation: nil,
                readError: "Platform workflow owner read failed path=\(platformWorkflowDocument.path) reason=\(error.localizedDescription)"
            )
        }
    }

    public func loadGuestAddressResource() async throws -> RuntimeGuestAddressResourceState {
        try await guestAddressClient.loadGuestAddressResource()
    }

    public func loadVMLifecycleResource() async throws -> RuntimeVMLifecycleResourceState {
        try await vmLifecycleClient.loadVMLifecycleResource()
    }

    public func controlRuntimeProvider(
        _ action: RuntimeProviderCommandAction
    ) async throws -> RuntimeProviderCommandResponse {
        let operationId = "provider-\(UUID().uuidString.lowercased())"
        let result: RuntimeCommandResult
        do {
            result = try await hostClient.controlRuntimeProvider(action)
        } catch {
            if runtimeProviderControlIsUnavailable(error) {
                throw RuntimeControlAPIReadHandlerError.runtimeProviderControlUnavailable(
                    error.localizedDescription
                )
            }
            return await failedRuntimeProviderCommand(
                operationId: operationId,
                action: action,
                kind: runtimeProviderControlFailureKind(error),
                message: "Runtime Provider control failed: \(error.localizedDescription)"
            )
        }

        guard result.exitCode == 0, result.executionIssue == nil else {
            return await failedRuntimeProviderCommand(
                operationId: operationId,
                action: action,
                kind: "runtime-provider-control-failed",
                message: runtimeProviderEffectFailureMessage(result)
            )
        }

        do {
            return RuntimeProviderCommandResponse(
                operationId: operationId,
                action: action,
                state: .completed,
                provider: try await vmLifecycleClient.loadVMLifecycleResource(),
                failure: nil
            )
        } catch {
            return RuntimeProviderCommandResponse(
                operationId: operationId,
                action: action,
                state: .failed,
                provider: .failed(readError: runtimeProviderLifecycleReadFailureMessage(error)),
                failure: PlatformCommandFailure(
                    kind: "runtime-provider-lifecycle-read-failed",
                    message: runtimeProviderLifecycleReadFailureMessage(error)
                )
            )
        }
    }

    private func failedRuntimeProviderCommand(
        operationId: String,
        action: RuntimeProviderCommandAction,
        kind: String,
        message: String
    ) async -> RuntimeProviderCommandResponse {
        let provider: RuntimeVMLifecycleResourceState
        do {
            provider = try await vmLifecycleClient.loadVMLifecycleResource()
        } catch {
            provider = .failed(readError: runtimeProviderLifecycleReadFailureMessage(error))
        }
        return RuntimeProviderCommandResponse(
            operationId: operationId,
            action: action,
            state: .failed,
            provider: provider,
            failure: PlatformCommandFailure(kind: kind, message: message)
        )
    }

    private func runtimeProviderControlIsUnavailable(_ error: Error) -> Bool {
        if error is RuntimeControlClientUnsupportedError {
            return true
        }
        guard let clientError = error as? RuntimeClientError else {
            return false
        }
        switch clientError {
        case .missingLauncher, .launcherNotExecutable:
            return true
        case .missingUninstaller,
             .launcherInspectionFailed,
             .uninstallerInspectionFailed,
             .uninstallerNotExecutable,
             .invalidBackupDeletionTarget,
             .logExportFailed,
             .guestControlUnavailable:
            return false
        }
    }

    private func runtimeProviderControlFailureKind(_ error: Error) -> String {
        if let clientError = error as? RuntimeClientError,
           case .launcherInspectionFailed = clientError {
            return "runtime-provider-control-preflight-failed"
        }
        return "runtime-provider-control-failed"
    }

    private func runtimeProviderEffectFailureMessage(_ result: RuntimeCommandResult) -> String {
        var details = ["exitCode=\(result.exitCode)"]
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            details.append("stderr=\(stderr)")
        }
        if let executionIssue = result.executionIssue {
            details.append(
                "executionIssue=\(executionIssue.kind.rawValue): \(executionIssue.message)"
            )
        }
        return "Runtime Provider effect failed \(details.joined(separator: " "))"
    }

    private func runtimeProviderLifecycleReadFailureMessage(_ error: Error) -> String {
        "Runtime Provider lifecycle read failed: \(error.localizedDescription)"
    }

    public func loadRuntimeOperationEvents(
        query: RuntimeOperationEventQuery
    ) async throws -> RuntimeOperationEventHistory {
        try await commandClient.loadRuntimeOperationEvents(query: query)
    }

    public func loadVitalDBObservationSnapshot() async throws -> RuntimeVitalDBObservationSnapshot {
        await readWorker.loadVitalDBObservationSnapshot()
    }

    public func loadVitalDBRecorders() async throws -> RuntimeVitalRecorderHistory {
        await readWorker.loadVitalDBRecorders()
    }

    public func loadVitalDBBeds() async throws -> RuntimeVitalBedHistory {
        await readWorker.loadVitalDBBeds()
    }

    public func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async throws -> RuntimeVitalRecorderActivityWindow {
        await readWorker.loadVitalDBRecorderActivityWindow(query: query)
    }

    public func loadVitalDBRelationships() async throws -> RuntimeVitalRelationshipHistory {
        await readWorker.loadVitalDBRelationships()
    }

    public func loadHealthStatus() async throws -> PlatformState {
        let settings = await readWorker.loadSettings()
        let status = await readWorker.loadHealthStatus(settings: settings)
        return RuntimeControlLocalAPIStatusAssembler.applyingLocalAPIStatus(
            to: status,
            read: localAPIStatus
        )
    }

    public func loadRuntimeProductSettings() async throws -> RuntimeProductSettingsRead {
        try await commandClient.loadRuntimeProductSettings()
    }

    public func loadRuntimePlatformSettings() async throws -> RuntimePlatformSettingsRead {
        RuntimePlatformSettingsRead(runtimeSettings: await readWorker.loadSettings())
    }

    public func applyRuntimePlatformSettings(
        _ settings: RuntimePlatformSettingsApplyDocument
    ) async throws -> RuntimeControlCommandResponse {
        let current = await readWorker.loadSettings()
        guard current.readIssues.isEmpty else {
            throw RuntimeControlAPIReadHandlerError.platformSettingsCurrentStateInvalid(
                current.readIssues.map { "\($0.source): \($0.message)" }
            )
        }
        return RuntimeControlCommandResponse(
            result: try await commandClient.applySettings(settings.applying(to: current))
        )
    }

    public func applyRuntimeProductSettings(
        _ settings: GuestRuntimeSettingsDocument
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await commandClient.applyRuntimeProductSettings(settings)
    }

    public func applyRuntimeAdminPassword(
        _ password: String
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await commandClient.applyRuntimeAdminPassword(password)
    }

    public func loadRuntimeRedisRelaySettings() async throws -> RuntimeRedisRelaySettingsRead {
        try await commandClient.loadRuntimeRedisRelaySettings()
    }

    public func applyRuntimeRedisRelaySettings(
        _ settings: RuntimeRedisRelaySettingsApplyRequest
    ) async throws -> RuntimeGuestControlServiceOperation {
        try await commandClient.applyRuntimeRedisRelaySettings(settings)
    }

    public func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        await readWorker.loadReleaseInfo()
    }

    public func loadInstallInfo() async throws -> RuntimeInstallInfo {
        await readWorker.loadInstallInfo()
    }

    public func loadLabScenarios() async throws -> RuntimeLabScenarioList {
        try await commandClient.loadLabScenarios()
    }

    public func loadLabVitalFiles() async throws -> RuntimeLabVitalFileList {
        try await commandClient.loadLabVitalFiles()
    }

    public func loadLabBeds() async throws -> RuntimeLabBedList {
        try await commandClient.loadLabBeds()
    }

    public func loadLabRecorders() async throws -> RuntimeLabRecorderList {
        try await commandClient.loadLabRecorders()
    }

    public func loadLabSessions() async throws -> RuntimeLabSessionList {
        try await commandClient.loadLabSessions()
    }

    public func createLabBeds(_ request: RuntimeLabBedCreateRequest) async throws -> RuntimeLabBedList {
        try await commandClient.createLabBeds(request)
    }

    public func deleteLabBeds(_ request: RuntimeLabBedDeleteRequest) async throws -> RuntimeLabBedList {
        try await commandClient.deleteLabBeds(request)
    }

    public func resetLabBeds() async throws -> RuntimeLabBedList {
        try await commandClient.resetLabBeds()
    }

    public func createLabRecorders(_ request: RuntimeLabRecorderCreateRequest) async throws -> RuntimeLabRecorderList {
        try await commandClient.createLabRecorders(request)
    }

    public func deleteLabRecorders(_ request: RuntimeLabRecorderDeleteRequest) async throws -> RuntimeLabRecorderList {
        try await commandClient.deleteLabRecorders(request)
    }

    public func resetLabRecorders() async throws -> RuntimeLabRecorderList {
        try await commandClient.resetLabRecorders()
    }

    public func hideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandClient.hideVitalDBRecorders(request)
    }

    public func unhideVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandClient.unhideVitalDBRecorders(request)
    }

    public func deleteVitalDBRecorders(_ request: RuntimeVitalDBRecorderVisibilityRequest) async throws -> RuntimeVitalRecorderHistory {
        try await commandClient.deleteVitalDBRecorders(request)
    }

    public func hideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        try await commandClient.hideVitalDBBeds(request)
    }

    public func unhideVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        try await commandClient.unhideVitalDBBeds(request)
    }

    public func deleteVitalDBBeds(_ request: RuntimeVitalDBBedVisibilityRequest) async throws -> RuntimeVitalBedHistory {
        try await commandClient.deleteVitalDBBeds(request)
    }

    public func createLabSession(_ request: RuntimeLabSessionCreateRequest) async throws -> RuntimeLabSessionResponse {
        try await commandClient.createLabSession(request)
    }

    public func loadLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await commandClient.loadLabSession(sessionId: sessionId)
    }

    public func startLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await commandClient.startLabSession(sessionId: sessionId)
    }

    public func stopLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await commandClient.stopLabSession(sessionId: sessionId)
    }

    public func finishLabSession(sessionId: String) async throws -> RuntimeLabSessionResponse {
        try await commandClient.finishLabSession(sessionId: sessionId)
    }

    public func startLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse {
        try await commandClient.startLabRecorder(sessionId: sessionId, recorderId: recorderId)
    }

    public func stopLabRecorder(sessionId: String, recorderId: String) async throws -> RuntimeLabRecorderResponse {
        try await commandClient.stopLabRecorder(sessionId: sessionId, recorderId: recorderId)
    }

    public func replayLabVitalFile(_ request: RuntimeLabVitalFileReplayRequest) async throws -> RuntimeLabSessionResponse {
        try await commandClient.replayLabVitalFile(request)
    }

    public func uploadLabVitalFiles(
        _ sources: [RuntimeLabVitalFileUploadSource]
    ) async throws -> RuntimeLabVitalFileLibraryUploadResponse {
        try await commandClient.uploadLabVitalFiles(sources)
    }

    public func listGuestServices() async throws -> RuntimeGuestControlServiceList {
        try await commandClient.listGuestServices()
    }

    public func guestStackStatus() async throws -> RuntimeGuestControlStackStatus {
        try await commandClient.guestStackStatus()
    }

    public func guestServiceStatus(_ service: String) async throws -> RuntimeGuestControlServiceStatus {
        try await commandClient.guestServiceStatus(service)
    }

    public func guestServiceResource(_ service: String) async throws -> RuntimeGuestServiceResource {
        try await commandClient.guestServiceResource(service)
    }

    public func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse {
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
        let settings = await readWorker.loadSettings()
        let status = await readWorker.loadPlatformState(settings: settings)
        return try await readWorker.loadBackups(latestBackupPath: status.latestBackup)
    }

    public func loadRedisBackups() async throws -> [RuntimeBackup] {
        try await readWorker.loadRedisBackups()
    }

    public func loadRuntimeDataBackups() async throws -> [RuntimeBackup] {
        try await readWorker.loadRuntimeDataBackups()
    }

    public func startGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await commandClient.startGuestService(request)
    }

    public func stopGuestService(_ request: RuntimeGuestServiceControlRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await commandClient.stopGuestService(request)
    }

    public func restartGuestService(_ request: RuntimeGuestServiceRestartRequest) async throws -> RuntimeGuestControlServiceOperation {
        try await commandClient.restartGuestService(request)
    }

    public func repairRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.repairRuntimeServices())
    }

    public func repairProxy() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.repairProxy())
    }

    public func repairDatastore() async throws -> RuntimeGuestControlServiceOperation {
        try await guestMaintenanceClient.requestDatastoreRepair()
    }

    public func repairVMDisk() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.repairVMDisk())
    }

    public func createRedisBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.createRedisBackup())
    }

    public func createRuntimeDataBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.createRuntimeDataBackup())
    }

    public func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse {
        let summary = await readWorker.updateBundleSummaryResult(url: try localFileURL(bundle))
        return RuntimeUpdateBundleSummaryResponse(
            summary: RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.notReported)
                .displayText(summary)
        )
    }

    public func verifyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.verifyUpdateBundle(url: try localFileURL(bundle)))
    }

    public func applyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        let result = try await hostClient.applyUpdateBundle(url: try localFileURL(bundle))
        if result.exitCode == 0 {
            scheduleHelperRelaunch()
        }
        return RuntimeControlCommandResponse(result: result)
    }

    public func rollbackBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.rollbackRuntime(backupURL: try localFileURL(backup)))
    }

    public func restoreRedisBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.restoreRedisBackup(backupURL: try localFileURL(backup)))
    }

    public func restoreRuntimeDataBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.restoreRuntimeDataBackup(backupURL: try localFileURL(backup)))
    }

    public func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.deleteBackup(url: try localFileURL(backup)))
    }

    public func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult {
        try await hostClient.exportLogs(to: try localFileURL(destination))
    }

    public func createPlatformSupportExport() async throws -> PlatformWorkflowOperation {
        let operationId = "workflow-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let startedAt = Self.timestamp(Date())
        try writePlatformWorkflow(PlatformWorkflowOperation(
            operationId: operationId,
            kind: .supportExport,
            state: .accepted,
            startedAt: startedAt,
            updatedAt: startedAt,
            release: nil,
            artifact: nil,
            failure: nil
        ))
        let operation = await createManagedPlatformSupportExport(
            in: supportDirectory,
            operationId: operationId,
            startedAt: startedAt
        ) { destination in
            try await hostClient.exportLogs(to: destination)
        }
        try writePlatformWorkflow(operation)
        return operation
    }

    private func writePlatformWorkflow(_ operation: PlatformWorkflowOperation) throws {
        let directory = platformWorkflowDocument.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(platformWorkflowDocument.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            let data = try JSONEncoder().encode(operation)
            try data.write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            _ = try FileManager.default.replaceItemAt(platformWorkflowDocument, withItemAt: temporary)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            try FileManager.default.moveItem(at: temporary, to: platformWorkflowDocument)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    public func acquireOperationLease(
        _ request: RuntimeOperationLeaseAcquireRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        try await operationLeaseClient.acquireOperationLease(request.document)
    }

    public func heartbeatOperationLease(
        _ request: RuntimeOperationLeaseHeartbeatRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        try await operationLeaseClient.heartbeatOperationLease(
            operationId: request.operationId,
            heartbeatAt: request.heartbeatAt,
            expiresAt: request.expiresAt
        )
    }

    public func releaseOperationLease(
        _ request: RuntimeOperationLeaseReleaseRequest
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        try await operationLeaseClient.releaseOperationLease(operationId: request.operationId)
    }

    public func putVMLifecycleResource(
        _ request: RuntimeVMLifecyclePutRequest
    ) async throws -> RuntimeVMLifecycleResourceState {
        try await vmLifecycleClient.putVMLifecycleResource(request.document)
    }

    public func putGuestAddressResource(
        _ request: RuntimeGuestAddressPutRequest
    ) async throws -> RuntimeGuestAddressResourceState {
        try await guestAddressClient.putGuestAddressResource(address: request.address)
    }

    public func uninstallRuntime(mode: RuntimeUninstallMode) async throws -> RuntimeControlCommandResponse {
        let response = RuntimeControlCommandResponse(result: try await commandClient.uninstallRuntime(mode: mode))
        if response.result.exitCode == 0 {
            scheduleHelperTermination()
        }
        return response
    }

    private func localFileURL(_ reference: RuntimeControlFileReference) throws -> URL {
        guard reference.kind == .localPath else {
            throw RuntimeControlAPIReadHandlerError.unsupportedFileReference(reference.kind.rawValue)
        }
        return URL(fileURLWithPath: reference.value)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

}
