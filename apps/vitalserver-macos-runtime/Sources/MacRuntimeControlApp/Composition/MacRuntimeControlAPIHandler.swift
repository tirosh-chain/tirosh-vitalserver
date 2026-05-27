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

    init(
        commandClient: any RuntimeControlClient,
        hostClient: any RuntimeHostClient,
        readWorker: MacHostRuntimeReadWorker
    ) {
        self.commandClient = commandClient
        self.hostClient = hostClient
        self.readWorker = readWorker
    }

    func loadCapabilities() async throws -> RuntimeControlCapabilities {
        commandClient.capabilities
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

    func createRedisBackup() async throws -> RuntimeControlCommandResponse {
        RuntimeControlCommandResponse(result: try await commandClient.createRedisBackup())
    }
}
