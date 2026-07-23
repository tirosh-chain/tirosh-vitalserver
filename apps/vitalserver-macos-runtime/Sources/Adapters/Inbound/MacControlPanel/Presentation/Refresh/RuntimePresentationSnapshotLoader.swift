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

    func loadSettings() async -> RuntimeSettings {
        let loadedSettings: RuntimeSettings
        if let snapshotReader {
            loadedSettings = await snapshotReader.loadSettings()
        } else {
            loadedSettings = controlClient.loadSettings()
        }
        return loadedSettings
    }

    func loadPlatformState(settings: RuntimeSettings) async -> PlatformState {
        if let snapshotReader {
            return await snapshotReader.loadPlatformState(settings: settings)
        }
        return controlClient.loadPlatformState(settings: settings)
    }

    func loadOperationState() async -> PlatformOperationState {
        if let snapshotReader {
            return await snapshotReader.loadOperationState()
        }
        return controlClient.loadOperationState()
    }

    func loadHealthStatus(settings: RuntimeSettings) async -> PlatformState {
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

    func loadVitalBeds() async -> RuntimeVitalBedHistory {
        if let snapshotReader {
            return await snapshotReader.loadVitalDBBeds()
        }
        return controlClient.loadVitalDBBeds()
    }

    func loadVitalRecorderActivityWindow(
        query: RuntimeVitalRecorderActivityWindowQuery
    ) async -> RuntimeVitalRecorderActivityWindow {
        if let snapshotReader {
            return await snapshotReader.loadVitalDBRecorderActivityWindow(query: query)
        }
        return controlClient.loadVitalDBRecorderActivityWindow(query: query)
    }

    func loadVitalRecorderVitalFiles(
        vrcode: String
    ) async -> RuntimeVitalRecorderVitalFileHistory {
        if let snapshotReader {
            return await snapshotReader.loadVitalDBRecorderVitalFiles(vrcode: vrcode)
        }
        return controlClient.loadVitalDBRecorderVitalFiles(vrcode: vrcode)
    }

    func loadRecorderObservabilityDetail(
        vrcode: String
    ) async -> RuntimeRecorderObservabilityDetail {
        if let snapshotReader {
            return await snapshotReader.loadRecorderObservabilityDetail(vrcode: vrcode)
        }
        return controlClient.loadRecorderObservabilityDetail(vrcode: vrcode)
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

    func loadRuntimeDataBackups() async throws -> [RuntimeBackup] {
        if let snapshotReader {
            return try await snapshotReader.loadRuntimeDataBackups()
        }
        return try hostClient.loadRuntimeDataBackups()
    }

    func loadRedisBackups() async throws -> [RuntimeBackup] {
        if let snapshotReader {
            return try await snapshotReader.loadRedisBackups()
        }
        return try hostClient.loadRedisBackups()
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
