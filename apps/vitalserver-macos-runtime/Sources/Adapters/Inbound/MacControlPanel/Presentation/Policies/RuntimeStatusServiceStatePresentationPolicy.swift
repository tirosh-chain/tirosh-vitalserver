import Contracts

public struct RuntimeStatusServiceStatePresentationPolicy {
    public init() {}

    public func shouldDisplayOperationStateInsteadOfServiceState(_ state: RuntimeServiceState?) -> Bool {
        switch state {
        case .readFailed, .permissionDenied, .unknown:
            return false
        default:
            return true
        }
    }

    public func serviceStateSeverity(_ state: RuntimeServiceState) -> RuntimeStatusReachabilityPolicy.Severity {
        switch state {
        case .loaded:
            return .healthy
        case .notLoaded, .readFailed, .permissionDenied:
            return .warning
        case .unknown:
            return .neutral
        }
    }
}
