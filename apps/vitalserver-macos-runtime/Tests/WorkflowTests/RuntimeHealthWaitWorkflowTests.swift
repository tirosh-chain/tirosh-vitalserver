import Application
import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeHealthWaitWorkflowTests: XCTestCase {
    func testWaitExecutesPortsAndCompletesWhenRuntimeBecomesHealthy() throws {
        let harness = HealthWaitWorkflowHarness(snapshots: [
            healthSnapshot(reasons: [.hostProxyHTTP("000")]),
            healthSnapshot(reasons: []),
        ])

        let outcome = try harness.workflow.wait(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: true,
                restartWatchdog: true
            ),
            context: harness.context,
            actions: harness.actions
        )

        XCTAssertEqual(outcome, .completed)
        XCTAssertTrue(harness.events.contains("sleep:3.0"))
        XCTAssertTrue(harness.events.contains("status:recovering:health:waiting for runtime health: host-proxy-http-000"))
        XCTAssertTrue(harness.events.contains("log:runtime health ok hostProxyHTTP=200"))
    }

    func testWaitExecutionPreservesEarlyFailureAndTimeoutWithoutWorkflowJudgement() {
        let failedEarly = HealthWaitWorkflowHarness(snapshots: [
            healthSnapshot(reasons: [.guestBootstrapFailed]),
        ])

        XCTAssertThrowsError(try failedEarly.workflow.wait(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: false,
                restartWatchdog: false
            ),
            context: failedEarly.context,
            actions: failedEarly.actions
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "runtime health failed early reason=guest-bootstrap-failed"
            )
        }
        XCTAssertTrue(failedEarly.events.contains("log:runtime health failed early reason=guest-bootstrap-failed"))

        let timedOut = HealthWaitWorkflowHarness(snapshots: [
            healthSnapshot(reasons: [.hostProxyHTTP("000")]),
            healthSnapshot(reasons: [.guestHTTP("000")]),
        ])
        XCTAssertThrowsError(try timedOut.workflow.wait(
            policy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: false,
                restartProxy: false,
                restartWatchdog: false
            ),
            context: timedOut.context,
            actions: timedOut.actions
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "runtime health timed out reasons=host-proxy-http-000, guest-http-000"
            )
        }
    }
}

private final class HealthWaitWorkflowHarness {
    let workflow = RuntimeHealthWaitWorkflow()
    let context = RuntimeHealthWaitWorkflowContext(
        timeoutSeconds: 6,
        pollIntervalSeconds: 3,
        progressEveryAttempts: 1
    )
    var snapshots: [RuntimeHealthSnapshot]
    var events: [String] = []
    var serviceStates: [RuntimeManagedService: RuntimeServiceState] = [
        .vm: .loaded,
        .guestLogSync: .loaded,
        .proxy: .loaded,
        .watchdog: .loaded,
    ]

    lazy var actions = RuntimeHealthWaitWorkflowActions(
        serviceStates: { services in
            Dictionary(uniqueKeysWithValues: services.map { service in
                (service, self.serviceStates[service] ?? .notLoaded)
            })
        },
        healthSnapshot: {
            if self.snapshots.count > 1 {
                return self.snapshots.removeFirst()
            }
            return self.snapshots[0]
        },
        writeStatusBestEffort: { status, operation, message in
            self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
        },
        sleep: { seconds in
            self.events.append("sleep:\(seconds)")
        },
        log: { message in
            self.events.append("log:\(message)")
        }
    )

    init(snapshots: [RuntimeHealthSnapshot]) {
        self.snapshots = snapshots
    }
}

private func healthSnapshot(reasons: [RuntimeFailureReason]) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: true,
        proxyExecutable: true,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmState: reasons.isEmpty ? .running : .unreachable,
        vmIP: "192.168.64.2",
        proxyPort: 18080,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}
