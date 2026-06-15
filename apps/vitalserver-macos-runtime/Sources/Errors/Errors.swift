public struct BoundaryFailure: Error, Equatable, Sendable {
    public let kind: FailureKind
    public let context: ErrorContext

    public init(kind: FailureKind, context: ErrorContext) {
        self.kind = kind
        self.context = context
    }
}
public struct ErrorContext: Equatable, Sendable {
    public let operation: String
    public let source: String?
    public let detail: String?

    public init(operation: String, source: String? = nil, detail: String? = nil) {
        self.operation = operation
        self.source = source
        self.detail = detail
    }
}

public enum FailureKind: Equatable, Sendable {
    case missing
    case invalid
    case failed
    case stale
    case permissionDenied
    case dependencyUnavailable
    case unknown
}

public enum RuntimeHostProxyPortCleanerError: Error, CustomStringConvertible, Equatable {
    case runtimeOperationFailed(String)

    public var description: String {
        switch self {
        case .runtimeOperationFailed(let message):
            return message
        }
    }
}

public enum RuntimeInstallVMRuntimeConfigurationError: Error, CustomStringConvertible, Equatable {
    case configInspectionFailed(path: String, reason: String)
    case unexpectedConfigPathState(path: String, state: String)

    public var description: String {
        switch self {
        case .configInspectionFailed(let path, let reason):
            return "vm runtime config inspection failed: \(path) reason=\(reason)"
        case .unexpectedConfigPathState(let path, let state):
            return "vm runtime config path state is unexpected: \(path) state=\(state)"
        }
    }
}
