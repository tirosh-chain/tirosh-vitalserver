import Contracts

public struct RuntimeStatusVMStatePresentationPolicy {
    public init() {}

    public func vmStateSeverity(_ value: RuntimeVMState?) -> RuntimeStatusReachabilityPolicy.Severity {
        switch value {
        case .running:
            return .healthy
        case .starting, .stale:
            return .warning
        case .notInstalled, .stopped, .unreachable, .failed:
            return .critical
        case .unknown, nil:
            return .neutral
        }
    }
}
