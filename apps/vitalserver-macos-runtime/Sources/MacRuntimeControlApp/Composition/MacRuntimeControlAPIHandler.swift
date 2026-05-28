import Foundation
import Contracts
import Core
import MacHostRuntimeAdapter
import RuntimeControl
import RuntimeControlAPI

@MainActor
struct MacRuntimeControlAPIHandler: RuntimeControlAPIReadHandler {
    private let commandClient: any RuntimeControlClient
    private let hostClient: any RuntimeHostClient
    private let readWorker: MacHostRuntimeReadWorker
    private let servesTestTools: Bool

    init(
        commandClient: any RuntimeControlClient,
        hostClient: any RuntimeHostClient,
        readWorker: MacHostRuntimeReadWorker,
        servesTestTools: Bool
    ) {
        self.commandClient = commandClient
        self.hostClient = hostClient
        self.readWorker = readWorker
        self.servesTestTools = servesTestTools
    }

    func loadCapabilities() async throws -> RuntimeControlCapabilities {
        var capabilities = commandClient.capabilities
        capabilities.canUseTestTools = servesTestTools
        return capabilities
    }

    func loadStatus() async throws -> RuntimeStatus {
        let settings = await readWorker.loadSettings()
        return await readWorker.loadStatus(settings: settings)
    }

    func loadEvents(query: RuntimeEventQuery) async throws -> RuntimeEventHistory {
        await readWorker.loadRuntimeEvents(query: query)
    }

    func loadVitalDBObservation() async throws -> VitalDBObservationDocument? {
        await readWorker.loadVitalDBObservation()
    }

    func loadVitalDBRecorders() async throws -> RuntimeVitalRecorderHistory {
        await readWorker.loadVitalDBRecorders()
    }

    func loadVitalDBRelationships() async throws -> RuntimeVitalRelationshipHistory {
        await readWorker.loadVitalDBRelationships()
    }

    func loadHealthStatus() async throws -> RuntimeStatus {
        let settings = await readWorker.loadSettings()
        return await readWorker.loadHealthStatus(settings: settings)
    }

    func loadSettings() async throws -> RuntimeSettings {
        await readWorker.loadSettings()
    }

    func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        await readWorker.loadReleaseInfo()
    }

    func loadInstallInfo() async throws -> RuntimeInstallInfo {
        await readWorker.loadInstallInfo()
    }

    func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse {
        RuntimeLogTextResponse(
            text: await hostClient.loadLogText(
                sourceID: request.source,
                helperMessage: request.helperMessage,
                lineLimit: request.lineLimit
            )
        )
    }

    func loadBackups() async throws -> [RuntimeBackup] {
        let settings = await readWorker.loadSettings()
        let status = await readWorker.loadStatus(settings: settings)
        return await readWorker.loadBackups(latestBackupPath: status.latestBackup)
    }

    func loadRedisBackups() async throws -> [RuntimeBackup] {
        await readWorker.loadRedisBackups()
    }

    func applySettings(_ settings: RuntimeSettings) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.applySettings(settings))
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

    func repairProxy(proxyPort: Int) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.repairProxy(proxyPort: proxyPort))
    }

    func repairDatastore() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.repairDatastore())
    }

    func createRedisBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.createRedisBackup())
    }

    func updateBundleSummary(bundle: RuntimeControlFileReference) async throws -> RuntimeUpdateBundleSummaryResponse {
        RuntimeUpdateBundleSummaryResponse(summary: await readWorker.updateBundleSummary(url: try localFileURL(bundle)))
    }

    func verifyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.verifyUpdateBundle(url: try localFileURL(bundle)))
    }

    func applyUpdateBundle(bundle: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.applyUpdateBundle(url: try localFileURL(bundle)))
    }

    func rollbackBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.rollbackRuntime(backupURL: try localFileURL(backup)))
    }

    func deleteBackup(_ backup: RuntimeControlFileReference) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await hostClient.deleteBackup(url: try localFileURL(backup)))
    }

    func exportLogs(destination: RuntimeControlFileReference) async throws -> RuntimeLogExportResult {
        try await hostClient.exportLogs(to: try localFileURL(destination))
    }

    func uninstallRuntime(clean: Bool) async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.uninstallRuntime(clean: clean))
    }

    private func localFileURL(_ reference: RuntimeControlFileReference) throws -> URL {
        guard reference.kind == .localPath else {
            throw RuntimeControlAPIHandlerError.unsupportedFileReference(reference.kind)
        }
        return URL(fileURLWithPath: reference.value)
    }
}

enum RuntimeControlAPIHandlerError: LocalizedError, Equatable {
    case unsupportedFileReference(RuntimeControlFileReferenceKind)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileReference(let kind):
            return "File reference kind \(kind.rawValue) is not supported by this local Runtime Control handler."
        }
    }
}
