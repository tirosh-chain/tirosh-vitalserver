import Foundation

public struct RedisBackupRequestDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestId: String
    public let requestedAt: String
    public let operation: RuntimeOperation

    public init(
        schemaVersion: Int = 2,
        requestId: String,
        requestedAt: String,
        operation: RuntimeOperation = .redisBackup
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.requestedAt = requestedAt
        self.operation = operation
    }
}

public struct RedisBackupResultDocument: Codable, Equatable, Sendable {
    public let requestId: String?
    public let status: DatastoreRepairStatus
    public let message: String?
    public let archive: String?

    public init(
        requestId: String? = nil,
        status: DatastoreRepairStatus,
        message: String? = nil,
        archive: String? = nil
    ) {
        self.requestId = requestId
        self.status = status
        self.message = message
        self.archive = archive
    }
}

public struct RedisRestoreRequestDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestId: String
    public let requestedAt: String
    public let operation: RuntimeOperation
    public let archive: String

    public init(
        schemaVersion: Int = 2,
        requestId: String,
        requestedAt: String,
        operation: RuntimeOperation = .redisRestore,
        archive: String
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.requestedAt = requestedAt
        self.operation = operation
        self.archive = archive
    }
}

public struct RedisRestoreResultDocument: Codable, Equatable, Sendable {
    public let requestId: String?
    public let status: DatastoreRepairStatus
    public let message: String?
    public let restoredArchive: String?

    public init(
        requestId: String? = nil,
        status: DatastoreRepairStatus,
        message: String? = nil,
        restoredArchive: String? = nil
    ) {
        self.requestId = requestId
        self.status = status
        self.message = message
        self.restoredArchive = restoredArchive
    }
}
