import RuntimeControl

public enum RuntimeHealthNotificationState: Equatable {
    case healthy
    case needsAttention
    case critical
    case starting
    case notInstalled

    public init(status: RuntimeStatus) {
        if RuntimeReadinessPolicy.isReady(status) {
            self = .healthy
        } else if !status.runtimeInstalled {
            self = .notInstalled
        } else if status.runtimeState == .critical {
            self = .critical
        } else if status.runtimeState == .degraded
            || status.runtimeState == .recovering
            || !status.failureReasons.isEmpty {
            self = .needsAttention
        } else {
            self = .starting
        }
    }
}
