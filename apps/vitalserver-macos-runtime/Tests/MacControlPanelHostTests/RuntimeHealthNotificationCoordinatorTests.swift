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

    private func notInstalledStatus() -> RuntimeStatus {
        RuntimeStatus()
    }

    private func startingStatus() -> RuntimeStatus {
        var status = RuntimeStatus()
        status.runtimeInstalled = true
        status.runtimeInstallationState = .executable
        status.runtimeState = RuntimeState.installing
        return status
    }

    private func criticalStatus() -> RuntimeStatus {
        var status = RuntimeStatus()
        status.runtimeInstalled = true
        status.runtimeInstallationState = .executable
        status.runtimeState = RuntimeState.critical
        return status
    }

    private func degradedStatus() -> RuntimeStatus {
        var status = RuntimeStatus()
        status.runtimeInstalled = true
        status.runtimeInstallationState = .executable
        status.runtimeState = RuntimeState.degraded
        return status
    }

    private func readyStatus() -> RuntimeStatus {
        var status = RuntimeStatus()
        status.runtimeInstalled = true
        status.runtimeInstallationState = .executable
        status.vmServiceLoaded = true
        status.proxyServiceLoaded = true
        status.watchdogServiceLoaded = true
        status.vmServiceState = .loaded
        status.proxyServiceState = .loaded
        status.watchdogServiceState = .loaded
        status.runtimeState = RuntimeState.healthy
        status.vmIP = "192.0.2.10"
        status.guestHTTP = "200"
        status.hostProxyHTTP = "200"
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
