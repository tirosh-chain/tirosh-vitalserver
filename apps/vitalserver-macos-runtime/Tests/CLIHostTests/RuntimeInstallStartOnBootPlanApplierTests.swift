import Contracts
import Application
import OutboundAdapters
import XCTest
import Errors

final class RuntimeInstallStartOnBootPlanApplierTests: XCTestCase {
    func testApplyExecutesEnableSleepPreventionPlan() throws {
        let events = EventLog()
        let applier = makeApplier(events: events)

        try applier.apply(plan: RuntimeInstallStartOnBootPlan(
            startOnBoot: true,
            sleepPreventionAction: .enable
        ))

        XCTAssertEqual(events.values, [
            "set-start-on-boot:true",
            "run:/bin/launchctl enable system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
    }

    func testApplyExecutesDisableSleepPreventionPlan() throws {
        let events = EventLog()
        let applier = makeApplier(events: events)

        try applier.apply(plan: RuntimeInstallStartOnBootPlan(
            startOnBoot: false,
            sleepPreventionAction: .disable
        ))

        XCTAssertEqual(events.values, [
            "set-start-on-boot:false",
            "run:/bin/launchctl disable system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
    }

    private func makeApplier(events: EventLog) -> RuntimeInstallStartOnBootPlanApplier {
        RuntimeInstallStartOnBootPlanApplier(
            context: RuntimeInstallStartOnBootPlanContext(
                launchctlExecutable: "/bin/launchctl"
            ),
            operations: RuntimeInstallStartOnBootPlanOperations(
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
