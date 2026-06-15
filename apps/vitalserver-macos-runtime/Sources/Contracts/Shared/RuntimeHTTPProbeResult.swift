public enum RuntimeHTTPProbeResult: Equatable, Sendable {
    case reportedStatus(String)
    case emptyStatus
    case outputInvalid(String)
    case commandFailed(String)

    public var statusText: String {
        switch self {
        case .reportedStatus(let status):
            return status
        case .emptyStatus:
            return "http-probe-empty-status"
        case .outputInvalid(let message):
            return "http-probe-output-invalid \(message)"
        case .commandFailed(let message):
            return "http-probe-command-failed \(message)"
        }
    }
}
