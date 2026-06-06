import Foundation

public enum RuntimeMigrationRunnerError: Error, CustomStringConvertible {
    case bundleVerificationFailed(String)

    public var description: String {
        switch self {
        case .bundleVerificationFailed(let message):
            return "bundle verification failed: \(message)"
        }
    }
}
