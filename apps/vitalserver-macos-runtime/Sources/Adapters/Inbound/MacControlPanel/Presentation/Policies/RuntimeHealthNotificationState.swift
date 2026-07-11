import RuntimeControl
import Errors

public enum RuntimeHealthNotificationState: Equatable {
    case healthy
    case needsAttention
    case critical
    case starting
    case notInstalled

    public init(status: PlatformState) {
        if RuntimeReadinessPolicy.isReady(status) {
            self = .healthy
        } else if !status.runtimeInstallationState.isExecutable {
            self = .notInstalled
        } else if status.platformHealth == .critical {
            self = .critical
        } else if status.platformHealth == .degraded
            || status.platformHealth == .recovering
            || !status.healthIssues.isEmpty {
            self = .needsAttention
        } else {
            self = .starting
        }
    }
}
