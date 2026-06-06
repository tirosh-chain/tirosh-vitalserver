public enum RuntimeProxyNginxPIDReadResult: Equatable {
    case loaded(String)
    case missing
    case empty
    case readFailed(String)

    public var loadedPID: String? {
        if case .loaded(let value) = self {
            return value
        }
        return nil
    }
}
