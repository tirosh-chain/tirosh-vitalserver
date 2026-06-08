import Contracts
import RuntimeControl
import Errors

enum RuntimeReleaseInfoLoadResult: Equatable {
    case loaded(RuntimeReleaseInfo)
    case unavailable
    case failed(String)
}

@MainActor
struct RuntimePresentationSnapshotLoader {
    let controlClient: any RuntimeControlClient
    let hostClient: any RuntimeHostClient
    let snapshotReader: (any RuntimeViewModelSnapshotReading)?
    let localAPISettings: (any RuntimeControlLocalAPISettingsApplying)?

    func loadSettings() async -> RuntimeSettings {
        let loadedSettings: RuntimeSettings
        if let snapshotReader {
            loadedSettings = await snapshotReader.loadSettings()
        } else {
            loadedSettings = controlClient.loadSettings()
        }
        return localAPISettings?.settingsWithLocalAPIPort(loadedSettings) ?? loadedSettings
    }

    func loadStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        if let snapshotReader {
            return await snapshotReader.loadStatus(settings: settings)
        }
        return controlClient.loadStatus(settings: settings)
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> RuntimeStatus {
        if let snapshotReader {
            return await snapshotReader.loadHealthStatus(settings: settings)
        }
        return await controlClient.loadHealthStatus(settings: settings)
    }

    func loadRuntimeEvents(query: RuntimeEventQuery) async -> RuntimeEventHistory {
        if let snapshotReader {
            return await snapshotReader.loadRuntimeEvents(query: query)
        }
        return controlClient.loadRuntimeEvents(query: query)
    }

    func loadVitalDBObservationSnapshot() async -> RuntimeVitalDBObservationSnapshot {
        if let snapshotReader {
            return await snapshotReader.loadVitalDBObservationSnapshot()
        }
        return controlClient.loadVitalDBObservationSnapshot()
    }

    func loadVitalRecorders() async -> RuntimeVitalRecorderHistory {
        if let snapshotReader {
            return await snapshotReader.loadVitalDBRecorderSummaries()
        }
        return controlClient.loadVitalDBRecorderSummaries()
    }

    func loadVitalRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async -> RuntimeVitalRecorderActivityWindow {
        if let snapshotReader {
            return await snapshotReader.loadVitalDBRecorderActivityWindow(query: query)
        }
        return controlClient.loadVitalDBRecorderActivityWindow(query: query)
    }

    func loadVitalRelationships() async -> RuntimeVitalRelationshipHistory {
        if let snapshotReader {
            return await snapshotReader.loadVitalDBRelationships()
        }
        return controlClient.loadVitalDBRelationships()
    }

    func loadBackups(latestBackupPath: String?) async throws -> [RuntimeBackup] {
        if let snapshotReader {
            return try await snapshotReader.loadBackups(latestBackupPath: latestBackupPath)
        }
        return try hostClient.loadBackups(latestBackupPath: latestBackupPath)
    }

    func loadReleaseInfoIfAvailable() async -> RuntimeReleaseInfoLoadResult {
        guard controlClient.capabilities.canViewReleaseMetadata else {
            return .unavailable
        }
        do {
            return .loaded(try await controlClient.loadReleaseInfo())
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
