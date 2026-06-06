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
