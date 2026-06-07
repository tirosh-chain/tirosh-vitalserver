import Foundation


public enum RuntimeControlAPIHandlerError: LocalizedError, Equatable {
    case unsupportedFileReference(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileReference(let kind):
            return "File reference kind \(kind) is not supported by this local Runtime Control handler."
        }
    }
}


public enum RuntimeControlLocalAPIServerLifecycleError: LocalizedError, Equatable {
    case failedToListen(port: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .failedToListen(let port, let reason):
            return "Remote Console API server failed to listen on port \(port): \(reason)"
        }
    }
}
