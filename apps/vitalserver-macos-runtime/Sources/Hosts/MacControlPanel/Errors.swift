import Foundation

public enum RuntimeControlLocalAPIServerLifecycleError: LocalizedError, Equatable {
    case failedToListen(port: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .failedToListen(let port, let reason):
            return "Remote Console API server failed to listen on port \(port): \(reason)"
        }
    }
}
