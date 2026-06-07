public enum RuntimeCommandOutputStream: String, Codable, Equatable, Sendable {
    case stdout
    case stderr
}

public struct RuntimeCommandOutputIssue: Codable, Equatable, Sendable {
    public let stream: RuntimeCommandOutputStream
    public let message: String

    public init(stream: RuntimeCommandOutputStream, message: String) {
        self.stream = stream
        self.message = message
    }
}
