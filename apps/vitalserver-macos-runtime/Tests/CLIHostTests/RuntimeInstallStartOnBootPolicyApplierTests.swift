import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeInstallStartOnBootPolicyApplierTests: XCTestCase {
    func testApplyEnablesSleepPreventionOnlyWhenStartOnBootAndSleepPreventionAreEnabled() throws {
        let events = EventLog()
        let applier = makeApplier(events: events)

        try applier.apply(input: RuntimeInstallStartOnBootPolicyInput(
            startOnBoot: true,
            preventSystemSleep: true
        ))

        XCTAssertEqual(events.values, [
            "set-start-on-boot:true",
            "run:/bin/launchctl enable system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
    }

    func testApplyDisablesSleepPreventionWhenStartOnBootIsDisabled() throws {
        let events = EventLog()
        let applier = makeApplier(events: events)

        try applier.apply(input: RuntimeInstallStartOnBootPolicyInput(
            startOnBoot: false,
            preventSystemSleep: true
        ))

        XCTAssertEqual(events.values, [
            "set-start-on-boot:false",
            "run:/bin/launchctl disable system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
    }

    func testApplyDisablesSleepPreventionWhenSleepPreventionIsDisabled() throws {
        let events = EventLog()
        let applier = makeApplier(events: events)

        try applier.apply(input: RuntimeInstallStartOnBootPolicyInput(
            startOnBoot: true,
            preventSystemSleep: false
        ))

        XCTAssertEqual(events.values, [
            "set-start-on-boot:true",
            "run:/bin/launchctl disable system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
    }

    private func makeApplier(events: EventLog) -> RuntimeInstallStartOnBootPolicyApplier {
        RuntimeInstallStartOnBootPolicyApplier(
            context: RuntimeInstallStartOnBootPolicyContext(
                launchctlExecutable: "/bin/launchctl"
            ),
            operations: RuntimeInstallStartOnBootPolicyOperations(
                setStartOnBoot: { enabled in
                    events.append("set-start-on-boot:\(enabled)")
                },
                runRequired: { executable, arguments in
                    events.append("run:\(executable) \(arguments.joined(separator: " "))")
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
