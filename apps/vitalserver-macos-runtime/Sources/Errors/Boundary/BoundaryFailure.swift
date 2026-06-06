public struct BoundaryFailure: Error, Equatable, Sendable {
    public let kind: FailureKind
    public let context: ErrorContext

    public init(kind: FailureKind, context: ErrorContext) {
        self.kind = kind
        self.context = context
    }
}
