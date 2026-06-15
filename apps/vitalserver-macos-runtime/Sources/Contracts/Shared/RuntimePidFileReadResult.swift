public enum RuntimePidFileReadResult: Equatable, Sendable {
    case missing
    case loaded(Int32)
    case pidFileInvalid(String)
    case readFailed(String)
}
