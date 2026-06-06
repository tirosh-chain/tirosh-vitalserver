import Contracts
import Errors

public struct RuntimeStatusReachabilityPolicy {
    public enum Reachability: Equatable, Sendable {
        case notReported
        case reachable
        case unavailable
        case unreachable
        case failed
    }

    public enum Severity: Equatable, Sendable {
        case healthy
        case warning
        case critical
        case neutral
    }

    public init() {}

    public func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    public func reachability(_ value: String?) -> Reachability {
        guard let value, !value.isEmpty else {
            return .notReported
        }
        if isSuccessfulHTTPStatus(value) {
            return .reachable
        }
        if Int(value) != nil {
            return .unavailable
        }
        if value == "failed" {
            return .unreachable
        }
        return .failed
    }

    public func httpSeverity(_ value: String?) -> Severity {
        guard let value, !value.isEmpty else {
            return .neutral
        }
        return isSuccessfulHTTPStatus(value) ? .healthy : .warning
    }

    public func shouldDisplayOperationStateInsteadOfServiceState(_ state: RuntimeServiceState?) -> Bool {
        switch state {
        case .readFailed, .permissionDenied, .unknown:
            return false
        default:
            return true
        }
    }

    public func serviceStateSeverity(_ state: RuntimeServiceState) -> Severity {
        switch state {
        case .loaded:
            return .healthy
        case .notLoaded, .readFailed, .permissionDenied:
            return .warning
        case .unknown:
            return .neutral
        }
    }

    public func vmStateSeverity(_ value: RuntimeVMState?) -> Severity {
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
