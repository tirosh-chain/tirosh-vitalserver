import Foundation

public enum RuntimeHealthCheckRunnerError: Error, CustomStringConvertible, Equatable {
    case runtimeHealthFailed

    public var description: String {
        switch self {
        case .runtimeHealthFailed:
            return "runtime health check failed"
        }
    }
}
