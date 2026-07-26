import Foundation

public struct RuntimeHostStateStoreMetadata: Equatable, Sendable {
    public let schemaVersion: Int
    public let databaseID: String
    public let createdAt: String
    public let updatedAt: String

    public init(
        schemaVersion: Int,
        databaseID: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.databaseID = databaseID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum RuntimeHostStateStoreFailureStage: String, Equatable, Sendable {
    case pathInspection = "path-inspection"
    case directoryPreparation = "directory-preparation"
    case open
    case configuration
    case migration
    case integrityCheck = "integrity-check"
    case metadataRead = "metadata-read"
    case transaction
}

public struct RuntimeHostStateStoreFailure: Equatable, Sendable {
    public let stage: RuntimeHostStateStoreFailureStage
    public let message: String

    public init(stage: RuntimeHostStateStoreFailureStage, message: String) {
        self.stage = stage
        self.message = message
    }
}

public enum RuntimeHostStateStoreReadResult: Equatable, Sendable {
    case missing
    case loaded(RuntimeHostStateStoreMetadata)
    case failed(RuntimeHostStateStoreFailure)
}

public protocol RuntimeHostStateStoreReadinessReading {
    func loadHostStateStoreReadiness() -> RuntimeHostStateStoreReadResult
}
