import Foundation
import Contracts
import InboundAdapters
import OutboundAdapters
import RuntimeControl
import Errors

@MainActor
struct MacRuntimeControlAPIHandler: RuntimeControlAPIReadHandler {
    private let commandClient: any RuntimeControlClient
    private let hostClient: any RuntimeHostClient
    private let readWorker: MacRuntimeControlReadWorker
    private let localAPISettings: RuntimeControlLocalAPISettingsCoordinator
    private let servesTestTools: Bool
    private let localAPIStatus: RuntimeControlLocalAPIStatusRead
    private let scheduleHelperRelaunch: @MainActor () -> Void
    private let scheduleHelperTermination: @MainActor () -> Void

    init(
        commandClient: any RuntimeControlClient,
        hostClient: any RuntimeHostClient,
        readWorker: MacRuntimeControlReadWorker,
        localAPISettings: RuntimeControlLocalAPISettingsCoordinator,
        servesTestTools: Bool,
        runtimeControlStartedAt: Date = Date(),
        scheduleHelperRelaunch: @escaping @MainActor () -> Void = {},
        scheduleHelperTermination: @escaping @MainActor () -> Void = {}
    ) {
        self.commandClient = commandClient
        self.hostClient = hostClient
        self.readWorker = readWorker
        self.localAPISettings = localAPISettings
        self.servesTestTools = servesTestTools
        self.localAPIStatus = RuntimeControlLocalAPIStatusRead.reachable(
            startedAt: Self.timestamp(runtimeControlStartedAt)
        )
        self.scheduleHelperRelaunch = scheduleHelperRelaunch
        self.scheduleHelperTermination = scheduleHelperTermination
    }

    func loadCapabilities() async throws -> RuntimeControlCapabilities {
        var capabilities = commandClient.capabilities
        capabilities.canUseTestTools = servesTestTools
        return capabilities
    }

    func loadStatus() async throws -> RuntimeStatus {
        let settings = await readWorker.loadSettings()
        let status = await readWorker.loadStatus(settings: settings)
        return RuntimeControlLocalAPIStatusAssembler.applyingLocalAPIStatus(
            to: status,
            read: localAPIStatus
        )
    }

    func loadEvents(query: RuntimeEventQuery) async throws -> RuntimeEventHistory {
        await readWorker.loadRuntimeEvents(query: query)
    }

    func loadVitalDBObservationSnapshot() async throws -> RuntimeVitalDBObservationSnapshot {
        await readWorker.loadVitalDBObservationSnapshot()
    }

    func loadVitalDBRecorders() async throws -> RuntimeVitalRecorderHistory {
        await readWorker.loadVitalDBRecorders()
    }

    func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async throws -> RuntimeVitalRecorderActivityWindow {
        await readWorker.loadVitalDBRecorderActivityWindow(query: query)
    }

    func loadVitalDBRelationships() async throws -> RuntimeVitalRelationshipHistory {
        await readWorker.loadVitalDBRelationships()
    }

    func loadHealthStatus() async throws -> RuntimeStatus {
        let settings = await readWorker.loadSettings()
        let status = await readWorker.loadHealthStatus(settings: settings)
        return RuntimeControlLocalAPIStatusAssembler.applyingLocalAPIStatus(
            to: status,
            read: localAPIStatus
        )
    }

    func loadSettings() async throws -> RuntimeSettings {
        localAPISettings.settingsWithLocalAPIPort(await readWorker.loadSettings())
    }

    func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        await readWorker.loadReleaseInfo()
    }

    func loadInstallInfo() async throws -> RuntimeInstallInfo {
        await readWorker.loadInstallInfo()
    }

    func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse {
        let textResult = await hostClient.loadLogTextResult(
            sourceID: request.source,
            lineLimit: request.lineLimit
        )
        return RuntimeLogTextResponse(
            text: RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.noLogData)
                .displayText(textResult)
        )
    }

    func loadBackups() async throws -> [RuntimeBackup] {
        let settings = await readWorker.loadSettings()
        let status = await readWorker.loadStatus(settings: settings)
        return try await readWorker.loadBackups(latestBackupPath: status.latestBackup)
    }

    func loadRedisBackups() async throws -> [RuntimeBackup] {
        try await readWorker.loadRedisBackups()
    }

    func loadRuntimeDataBackups() async throws -> [RuntimeBackup] {
        try await readWorker.loadRuntimeDataBackups()
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeControlCommandResponse {
        let response = RuntimeControlCommandResponse(result: try await commandClient.applySettings(settings))
        localAPISettings.apply(settings: settings)
        return response
    }

    func startRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.startRuntimeServices())
    }

    func stopRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.stopRuntimeServices())
    }

    func repairRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.repairRuntimeServices())
    }

    func repairProxy() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.repairProxy())
    }

    func repairDatastore() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.repairDatastore())
    }

    func repairVMDisk() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.repairVMDisk())
    }

    func createRedisBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.createRedisBackup())
    }

    func createRuntimeDataBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.createRuntimeDataBackup())
    }

    func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse {
        let summary = await readWorker.updateBundleSummaryResult(url: try localFileURL(bundle))
        return RuntimeUpdateBundleSummaryResponse(
            summary: RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.notReported)
                .displayText(summary)
        )
    }

    func verifyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.verifyUpdateBundle(url: try localFileURL(bundle)))
    }

    func applyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        let result = try await hostClient.applyUpdateBundle(url: try localFileURL(bundle))
        if result.exitCode == 0 {
            scheduleHelperRelaunch()
        }
        return RuntimeControlCommandResponse(result: result)
    }

    func rollbackBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.rollbackRuntime(backupURL: try localFileURL(backup)))
    }

    func restoreRedisBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.restoreRedisBackup(backupURL: try localFileURL(backup)))
    }

    func restoreRuntimeDataBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.restoreRuntimeDataBackup(backupURL: try localFileURL(backup)))
    }

    func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.deleteBackup(url: try localFileURL(backup)))
    }

    func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult {
        try await hostClient.exportLogs(to: try localFileURL(destination))
    }

    func uninstallRuntime(clean: Bool) async throws -> RuntimeControlCommandResponse {
        let response = RuntimeControlCommandResponse(result: try await commandClient.uninstallRuntime(clean: clean))
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
