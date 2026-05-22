final class RuntimeHealthNotificationCoordinator {
    private let notifier: any HealthNotifying
    private var baseline: RuntimeHealthNotificationState?

    init(notifier: any HealthNotifying) {
        self.notifier = notifier
    }

    func handleTransition(to status: RuntimeStatus) {
        let next = RuntimeHealthNotificationState(status: status)
        guard let previous = baseline else {
            baseline = next
            return
        }
        guard previous != next else {
            return
        }
        baseline = next

        switch next {
        case .critical:
            notifier.notify(
                title: AppConstants.Notifications.criticalTitle,
                body: status.displayMessage ?? AppConstants.Notifications.criticalBody
            )
        case .needsAttention:
            notifier.notify(
                title: AppConstants.Notifications.needsAttentionTitle,
                body: status.displayMessage ?? AppConstants.Notifications.needsAttentionBody
            )
        case .healthy where previous == .critical || previous == .needsAttention:
            notifier.notify(
                title: AppConstants.Notifications.recoveredTitle,
                body: AppConstants.Notifications.recoveredBody
            )
        default:
            break
        }
    }
}

enum RuntimeHealthNotificationState: Equatable {
    case healthy
    case needsAttention
    case critical
    case starting
    case notInstalled

    init(status: RuntimeStatus) {
        if status.isReady {
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
