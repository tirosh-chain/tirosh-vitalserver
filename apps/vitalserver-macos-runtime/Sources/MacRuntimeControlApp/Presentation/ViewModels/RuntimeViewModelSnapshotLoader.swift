import Contracts
import MacHostRuntimeAdapter
import RuntimeControl

@MainActor
struct RuntimeViewModelSnapshotLoader {
    let controlClient: any RuntimeControlClient
    let hostClient: any RuntimeHostClient
    let readWorker: MacHostRuntimeReadWorker?
    let localAPISettings: RuntimeControlLocalAPISettingsCoordinator?

    func loadSettings() async -> RuntimeSettings {
        let loadedSettings: RuntimeSettings
        if let readWorker {
            loadedSettings = await readWorker.loadSettings()
        } else {
            loadedSettings = controlClient.loadSettings()
        }
        return localAPISettings?.settingsWithLocalAPIPort(loadedSettings) ?? loadedSettings
    }

    func loadStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        if let readWorker {
            return await readWorker.loadStatus(settings: settings)
        }
        return controlClient.loadStatus(settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        if let readWorker {
            return await readWorker.loadHealthStatus(settings: settings)
        }
        return await controlClient.loadHealthStatus(settings: settings)
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) async -> RuntimeEventHistory {
        if let readWorker {
            return await readWorker.loadRuntimeEvents(query: query)
        }
        return controlClient.loadRuntimeEvents(query: query)
    }

    func loadVitalDBObservationSnapshot() async -> RuntimeVitalDBObservationSnapshot {
        if let readWorker {
            return await readWorker.loadVitalDBObservationSnapshot()
        }
        return controlClient.loadVitalDBObservationSnapshot()
    }

    func loadVitalRecorders() async -> RuntimeVitalRecorderHistory {
        if let readWorker {
            return await readWorker.loadVitalDBRecorders()
        }
        return controlClient.loadVitalDBRecorders()
    }

    func loadVitalRelationships() async -> RuntimeVitalRelationshipHistory {
        if let readWorker {
            return await readWorker.loadVitalDBRelationships()
        }
        return controlClient.loadVitalDBRelationships()
    }

    func loadBackups(latestBackupPath: String?) async throws -> [RuntimeBackup] {
        if let readWorker {
            return try await readWorker.loadBackups(latestBackupPath: latestBackupPath)
        }
        return try hostClient.loadBackups(latestBackupPath: latestBackupPath)
    }

    func loadReleaseInfoIfAvailable() async -> RuntimeReleaseInfo? {
        guard controlClient.capabilities.canViewReleaseMetadata else {
            return nil
        }
        return try? await controlClient.loadReleaseInfo()
    }
}
