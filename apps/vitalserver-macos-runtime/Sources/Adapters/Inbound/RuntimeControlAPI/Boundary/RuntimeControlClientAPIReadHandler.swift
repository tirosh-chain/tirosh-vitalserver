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

    public func loadCapabilities() async throws -> RuntimeControlCapabilities {
        client.capabilities
    }

    public func loadStatus() async throws -> RuntimeStatus {
        let settings = client.loadSettings()
        return client.loadStatus(settings: settings)
    }

    public func loadEvents(query: RuntimeEventQuery) async throws -> RuntimeEventHistory {
        client.loadRuntimeEvents(query: query)
    }

    public func loadVitalDBObservationSnapshot() async throws -> RuntimeVitalDBObservationSnapshot {
        client.loadVitalDBObservationSnapshot()
    }

    public func loadVitalDBRecorders() async throws -> RuntimeVitalRecorderHistory {
        client.loadVitalDBRecorders()
    }

    public func loadVitalDBRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async throws -> RuntimeVitalRecorderActivityWindow {
        client.loadVitalDBRecorderActivityWindow(query: query)
    }

    public func loadVitalDBRelationships() async throws -> RuntimeVitalRelationshipHistory {
        client.loadVitalDBRelationships()
    }

    public func loadHealthStatus() async throws -> RuntimeStatus {
        let settings = client.loadSettings()
        return await client.loadHealthStatus(settings: settings)
    }

    public func loadSettings() async throws -> RuntimeSettings {
        client.loadSettings()
    }

    public func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        try await client.loadReleaseInfo()
    }

    public func loadInstallInfo() async throws -> RuntimeInstallInfo {
        client.loadInstallInfo()
    }

    public func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
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
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        let settings = client.loadSettings()
        let status = client.loadStatus(settings: settings)
        return try hostClient.loadBackups(latestBackupPath: status.latestBackup)
    }

    public func loadRedisBackups() async throws -> [RuntimeBackup] {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return try hostClient.loadRedisBackups()
    }

    public func loadRuntimeDataBackups() async throws -> [RuntimeBackup] {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return try hostClient.loadRuntimeDataBackups()
    }

    public func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.applySettings(settings))
    }

    public func startRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.startRuntimeServices())
    }

    public func stopRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.stopRuntimeServices())
    }

    public func repairRuntimeServices() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.repairRuntimeServices())
    }

    public func repairProxy() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.repairProxy())
    }

    public func repairDatastore() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.repairDatastore())
    }

    public func repairVMDisk() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.repairVMDisk())
    }

    public func createRedisBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.createRedisBackup())
    }

    public func createRuntimeDataBackup() async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.createRuntimeDataBackup())
    }

    public func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        let summary = hostClient.updateBundleSummaryResult(url: try localFileURL(bundle))
        return RuntimeUpdateBundleSummaryResponse(
            summary: RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.notReported)
                .displayText(summary)
        )
    }

    public func verifyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.verifyUpdateBundle(url: try localFileURL(bundle)))
    }

    public func applyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.applyUpdateBundle(url: try localFileURL(bundle)))
    }

    public func rollbackBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.rollbackRuntime(backupURL: try localFileURL(backup)))
    }

    public func restoreRedisBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.restoreRedisBackup(backupURL: try localFileURL(backup)))
    }

    public func restoreRuntimeDataBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.restoreRuntimeDataBackup(backupURL: try localFileURL(backup)))
    }

    public func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeControlCommandResponse(result: try await hostClient.deleteBackup(url: try localFileURL(backup)))
    }

    public func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return try await hostClient.exportLogs(to: try localFileURL(destination))
    }

    public func uninstallRuntime(clean: Bool) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.uninstallRuntime(clean: clean))
    }

    private func localFileURL(_ reference: RuntimeControlFileReference) throws -> URL {
        guard reference.kind == .localPath else {
            throw RuntimeControlAPIReadHandlerError.unsupportedFileReference(reference.kind.rawValue)
        }
        return URL(fileURLWithPath: reference.value)
    }
}
