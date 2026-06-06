import Foundation

public enum RuntimeRedisBackupWorkflowError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}
