import RuntimeControl
import Errors

final class RuntimeHealthNotificationCoordinator {
    private let notifier: any HealthNotifying
    private let formatter = RuntimePresentationFormatter()
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
                body: formatter.statusDisplayMessage(status) ?? AppConstants.Notifications.criticalBody
            )
        case .needsAttention:
            notifier.notify(
                title: AppConstants.Notifications.needsAttentionTitle,
                body: formatter.statusDisplayMessage(status) ?? AppConstants.Notifications.needsAttentionBody
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
