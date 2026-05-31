import Foundation
import RuntimeControl
import Contracts

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
        return RuntimeLogTextResponse(
            text: await hostClient.loadLogText(
                sourceID: request.source,
                helperMessage: request.helperMessage,
                lineLimit: request.lineLimit
            )
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

    public func repairProxy(proxyPort: Int) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await client.repairProxy(proxyPort: proxyPort))
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

    public func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeUpdateBundleSummaryResponse(summary: hostClient.updateBundleSummary(url: try localFileURL(bundle)))
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
            throw RuntimeControlAPIReadHandlerError.unsupportedFileReference(reference.kind)
        }
        return URL(fileURLWithPath: reference.value)
    }
}

public enum RuntimeControlAPIReadHandlerError: LocalizedError, Equatable {
    case hostAffordanceUnavailable
    case unsupportedFileReference(RuntimeControlFileReferenceKind)

    public var errorDescription: String? {
        switch self {
        case .hostAffordanceUnavailable:
            return "Host affordance client is unavailable."
        case .unsupportedFileReference(let kind):
            return "File reference kind \(kind.rawValue) is not supported by this local Runtime Control handler."
        }
    }
}
