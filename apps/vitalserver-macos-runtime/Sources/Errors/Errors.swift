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
