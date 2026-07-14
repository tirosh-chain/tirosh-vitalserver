import Foundation

public enum RuntimeOperationLeaseLegacyMigrationResult: Equatable, Sendable {
    case sourceMissing
    case imported(operationId: String, archivePath: String)
    case alreadyCompleted(sourceState: String, archivePath: String?)
}

public protocol RuntimeOperationLeaseLegacyMigrating {
    func migrate() throws -> RuntimeOperationLeaseLegacyMigrationResult
}
