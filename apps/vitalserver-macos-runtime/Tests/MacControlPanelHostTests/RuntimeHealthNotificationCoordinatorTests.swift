import RuntimeControl
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeHealthNotificationCoordinatorTests: XCTestCase {
    func testFirstStatusEstablishesBaselineWithoutNotification() {
        let notifier = CapturingHealthNotifier()
        let coordinator = RuntimeHealthNotificationCoordinator(notifier: notifier)

        coordinator.handleTransition(to: notInstalledStatus())

        XCTAssertEqual(notifier.notifications, [])
    }

    func testCriticalTransitionSendsCriticalNotification() {
        let notifier = CapturingHealthNotifier()
        let coordinator = RuntimeHealthNotificationCoordinator(notifier: notifier)

        coordinator.handleTransition(to: startingStatus())
        coordinator.handleTransition(to: criticalStatus())

        XCTAssertEqual(notifier.notifications, [
            CapturedNotification(
                title: AppConstants.Notifications.criticalTitle,
                body: AppConstants.Notifications.criticalBody
            ),
        ])
    }

    func testDegradedTransitionSendsNeedsAttentionNotification() {
        let notifier = CapturingHealthNotifier()
        let coordinator = RuntimeHealthNotificationCoordinator(notifier: notifier)

        coordinator.handleTransition(to: startingStatus())
        coordinator.handleTransition(to: degradedStatus())

        XCTAssertEqual(notifier.notifications, [
            CapturedNotification(
                title: AppConstants.Notifications.needsAttentionTitle,
                body: AppConstants.Notifications.needsAttentionBody
            ),
        ])
    }

    func testRecoveryNotificationIsSentOnlyFromAttentionStates() {
        let notifier = CapturingHealthNotifier()
        let coordinator = RuntimeHealthNotificationCoordinator(notifier: notifier)

        coordinator.handleTransition(to: criticalStatus())
        coordinator.handleTransition(to: readyStatus())
        coordinator.handleTransition(to: startingStatus())
        coordinator.handleTransition(to: readyStatus())

        XCTAssertEqual(notifier.notifications, [
            CapturedNotification(
                title: AppConstants.Notifications.recoveredTitle,
                body: AppConstants.Notifications.recoveredBody
            ),
        ])
    }

    private func notInstalledStatus() -> PlatformState {
        platformState()
    }

    private func startingStatus() -> PlatformState {
        var status = platformState()
        status.runtimeInstallationState = .executable
        status.platformHealth = RuntimeState.installing
        return status
    }

    private func criticalStatus() -> PlatformState {
        var status = platformState()
        status.runtimeInstallationState = .executable
        status.platformHealth = RuntimeState.critical
        return status
    }

    private func degradedStatus() -> PlatformState {
        var status = platformState()
        status.runtimeInstallationState = .executable
        status.platformHealth = RuntimeState.degraded
        return status
    }

    private func readyStatus() -> PlatformState {
        var status = platformState()
        status.runtimeInstallationState = .executable
        status.services = [
            PlatformServiceStatus(role: .runtimeProvider, state: .loaded),
            PlatformServiceStatus(role: .publicProxy, state: .loaded),
            PlatformServiceStatus(role: .watchdog, state: .loaded),
        ]
        status.platformHealth = RuntimeState.healthy
        status.runtimeEndpoint = "192.0.2.10"
        status.runtimeControllerHTTP = "200"
        status.publicProxyHTTP = "200"
        return status
    }
}

private struct CapturedNotification: Equatable {
    let title: String
    let body: String
}

private final class CapturingHealthNotifier: HealthNotifying {
    var notifications: [CapturedNotification] = []

    func configure() {}

    func notify(title: String, body: String) {
        notifications.append(CapturedNotification(title: title, body: body))
    }
}
