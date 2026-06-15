public struct RuntimeHostProxyListener: Codable, Equatable, Sendable {
    public let command: String
    public let pid: String

    public init(command: String, pid: String) {
        self.command = command
        self.pid = pid
    }

    public var slashDescription: String {
        "\(command)/\(pid)"
    }

    public var hyphenDescription: String {
        "\(command)-\(pid)"
    }
}

public enum RuntimeHostProxyListenerScanResult: Equatable, Sendable {
    case clear
    case loaded([RuntimeHostProxyListener])
    case unavailable
    case inspectionFailed(String)
    case commandFailed(exitCode: Int32, reason: String)
    case malformedOutput(exitCode: Int32, reason: String)
}
