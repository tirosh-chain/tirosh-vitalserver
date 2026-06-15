import Contracts

public enum RuntimeStatusFailureReasonPolicy {
    public static func failureReasons(
        status: RuntimeStatusLevel,
        snapshot: RuntimeHealthSnapshot
    ) -> [RuntimeFailureReason] {
        switch status {
        case .installing, .initializing:
            return []
        case .updating, .recovering, .healthy, .degraded, .critical, .unknown:
            return snapshot.failureReasons
        }
    }
}
