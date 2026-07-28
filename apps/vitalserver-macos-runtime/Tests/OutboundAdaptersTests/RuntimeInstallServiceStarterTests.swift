import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeInstallServiceStarterTests: XCTestCase {
    func testStartSkipsServicesWhenStartAfterInstallIsDisabled() throws {
        let events = EventLog()
        let starter = makeStarter(events: events)

        try starter.start(input: RuntimeInstallServiceStartInput(
            startAfterInstall: false,
            preventSystemSleep: true
        ))

        XCTAssertEqual(events.values, [
            "start:\(RuntimeManagedService.updateHandoffSupervisor.label)",
            "log:start after install disabled",
        ])
    }

    func testStartLaunchesSleepPreventionThenRuntimeServicesAndCleansProxyPortBeforeProxy() throws {
        let events = EventLog()
        let starter = makeStarter(events: events)

        try starter.start(input: RuntimeInstallServiceStartInput(
            startAfterInstall: true,
            preventSystemSleep: true
        ))

        XCTAssertEqual(events.values, [
            "start:\(RuntimeManagedService.updateHandoffSupervisor.label)",
            "start:\(RuntimeManagedService.sleepPrevention.label)",
            "start:\(RuntimeManagedService.platformAgent.label)",
            "start:\(RuntimeManagedService.vm.label)",
            "start:\(RuntimeManagedService.guestLogSync.label)",
            "start:\(RuntimeManagedService.watchdog.label)",
            "cleanup-proxy-port",
            "start:\(RuntimeManagedService.proxy.label)",
        ])
    }

    func testStartDoesNotLaunchSleepPreventionWhenSystemSleepIsAllowed() throws {
        let events = EventLog()
        let starter = makeStarter(events: events)

        try starter.start(input: RuntimeInstallServiceStartInput(
            startAfterInstall: true,
            preventSystemSleep: false
        ))

        XCTAssertFalse(events.values.contains("start:\(RuntimeManagedService.sleepPrevention.label)"))
        XCTAssertEqual(
            events.values.prefix(2),
            [
                "start:\(RuntimeManagedService.updateHandoffSupervisor.label)",
                "start:\(RuntimeManagedService.platformAgent.label)",
            ]
        )
    }

    private func makeStarter(events: EventLog) -> RuntimeInstallServiceStarter {
        RuntimeInstallServiceStarter(
            operations: RuntimeInstallServiceStartOperations(
                startLaunchdService: { service in
                    events.append("start:\(service.label)")
                },
                cleanupHostProxyPortBeforeStart: {
                    events.append("cleanup-proxy-port")
                },
                log: { message in
                    events.append("log:\(message)")
                }
            )
        )
    }

    private final class EventLog {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }
}
