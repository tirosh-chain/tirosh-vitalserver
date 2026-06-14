import Contracts
import Foundation

public struct SQLiteRuntimeObservabilityStore {
    public static let schemaVersion = 5

    public let url: URL
    let database: SQLiteRuntimeObservabilityConnection
    private let migrationAppliedAt: @Sendable () -> String
    let relationshipProjectionPlanner: VitalDBRelationshipProjectionPlanning?

    public init(
        url: URL,
        migrationAppliedAt: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        },
        relationshipProjectionPlanner: VitalDBRelationshipProjectionPlanning? = nil
    ) {
        self.url = url
        self.database = SQLiteRuntimeObservabilityConnection(url: url)
        self.migrationAppliedAt = migrationAppliedAt
        self.relationshipProjectionPlanner = relationshipProjectionPlanner
    }

    public func initialize() throws {
        try database.withDatabase { db in
            try SQLiteRuntimeObservabilitySchema.apply(
                db,
                version: Self.schemaVersion,
                appliedAt: migrationAppliedAt()
            )
        }
    }
}
