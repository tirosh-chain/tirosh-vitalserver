import Application
import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeHealthWaitWorkflowTests: XCTestCase {
    func testWaitSkipsWhenNoServiceRestarted() throws {
        let harness = HealthWaitWorkflowHarness(snapshots: [healthSnapshot(reasons: [])])

        try harness.workflow.wait(for: RuntimeServiceRestartPolicy(
            restartVM: false,
            restartGuestLogSync: false,
            restartProxy: false,
            restartWatchdog: false
        ))

        XCTAssertEqual(harness.events, [
            "log:runtime services were not running before apply; skipping health wait",
        ])
    }

    func testWaitWritesProgressAndCompletesWhenHealthBecomesHealthy() throws {
        let harness = HealthWaitWorkflowHarness(snapshots: [
            healthSnapshot(reasons: [.hostProxyHTTP("000")]),
            healthSnapshot(reasons: []),
        ])

        try harness.workflow.wait(for: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: true,
            restartWatchdog: true
        ))

        XCTAssertTrue(harness.events.contains("sleep"))
        XCTAssertTrue(harness.events.contains("status:recovering:health:waiting for runtime health: host-proxy-http-000"))
        XCTAssertTrue(harness.events.contains("log:runtime health ok hostProxyHTTP=200"))
    }

    func testWaitFailsEarlyOnGuestBootstrapFailure() {
        let harness = HealthWaitWorkflowHarness(snapshots: [
            healthSnapshot(reasons: [.guestBootstrapFailed]),
        ])

        XCTAssertThrowsError(try harness.workflow.wait(for: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: false
        ))) { error in
            XCTAssertEqual(
                String(describing: error),
                "runtime health failed early reason=guest-bootstrap-failed"
            )
        }
        XCTAssertTrue(harness.events.contains("log:runtime health failed early reason=guest-bootstrap-failed"))
    }

    func testWaitRequiresGuestLogSyncServiceToLoad() {
        let harness = HealthWaitWorkflowHarness(snapshots: [healthSnapshot(reasons: [])])
        harness.serviceStates[.guestLogSync] = .notLoaded

        XCTAssertThrowsError(try harness.workflow.wait(for: RuntimeServiceRestartPolicy(
            restartVM: false,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: false
        ))) { error in
            XCTAssertTrue(String(describing: error).contains("guest-log-sync-service-not-loaded"))
        }
    }
}

private final class HealthWaitWorkflowHarness {
    var snapshots: [RuntimeHealthSnapshot]
    var events: [String] = []
    var serviceStates: [RuntimeManagedService: RuntimeServiceState] = [
        .vm: .loaded,
        .guestLogSync: .loaded,
        .proxy: .loaded,
        .watchdog: .loaded,
    ]

    init(snapshots: [RuntimeHealthSnapshot]) {
        self.snapshots = snapshots
    }

    var workflow: RuntimeHealthWaitWorkflow {
        RuntimeHealthWaitWorkflow(
            useCase: WaitForRuntimeHealthUseCase(),
            reader: RuntimeHealthWaitReader(
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
                }
            ),
            configuration: RuntimeHealthWaitWorkflowConfiguration(
                timeoutSeconds: 6,
                pollIntervalSeconds: 3,
                progressEveryAttempts: 1
            ),
            writer: RuntimeHealthWaitWriter(
                writeStatusBestEffort: { status, operation, message in
                    self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
                },
                sleep: {
                    self.events.append("sleep")
                },
                log: { message in
                    self.events.append("log:\(message)")
                }
            )
        )
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
