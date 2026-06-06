public enum FailureKind: Equatable, Sendable {
    case missing
    case invalid
    case failed
    case stale
    case permissionDenied
    case dependencyUnavailable
    case unknown
}
