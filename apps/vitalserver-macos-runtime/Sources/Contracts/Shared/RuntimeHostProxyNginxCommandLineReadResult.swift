public enum RuntimeHostProxyNginxCommandLineReadResult: Equatable, Sendable {
    case loaded(String)
    case empty
    case readFailed(String)
}
