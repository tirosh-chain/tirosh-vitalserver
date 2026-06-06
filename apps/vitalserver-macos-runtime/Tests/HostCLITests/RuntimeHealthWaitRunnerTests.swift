import Core
import Contracts
@testable import HostCLI
import Workflow
import XCTest

final class RuntimeHealthWaitRunnerTests: XCTestCase {
    func testWaitSkipsWhenNoServiceRestarted() throws {
        let harness = HealthWaitHarness(snapshots: [healthSnapshot(reasons: [])])

        try harness.runner.wait(for: RuntimeServiceRestartPolicy(
            restartVM: false,
            restartGuestLogSync: false,
            restartProxy: false,
            restartWatchdog: false
        ))

        XCTAssertEqual(harness.events, [
            "log:runtime services were not running before apply; skipping health wait",
        ])
    }

    func testWaitCompletesWhenHealthBecomesHealthy() throws {
        let harness = HealthWaitHarness(snapshots: [
            healthSnapshot(reasons: [.hostProxyHTTP("000")]),
            healthSnapshot(reasons: []),
        ])

        try harness.runner.wait(for: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: true,
            restartWatchdog: true
        ))

        XCTAssertTrue(harness.events.contains("sleep"))
        XCTAssertTrue(harness.events.contains("log:runtime health ok hostProxyHTTP=200"))
    }

    func testWaitThrowsWhenHealthFailsEarly() {
        let harness = HealthWaitHarness(snapshots: [
            healthSnapshot(reasons: [.guestBootstrapFailed]),
        ])

        XCTAssertThrowsError(try harness.runner.wait(for: RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: false
        ))) { error in
            XCTAssertEqual(String(describing: error), String(describing: RuntimeHealthWaitRunnerError.runtimeHealthFailed))
        }
        XCTAssertTrue(harness.events.contains("log:runtime health failed early reason=guest-bootstrap-failed"))
    }

    func testWaitDoesNotCompleteUntilGuestLogSyncServiceIsLoaded() {
        let harness = HealthWaitHarness(snapshots: [healthSnapshot(reasons: [])])
        harness.loadedServices.remove(.guestLogSync)

        XCTAssertThrowsError(try harness.runner.wait(for: RuntimeServiceRestartPolicy(
            restartVM: false,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: false
        ))) { error in
            XCTAssertEqual(String(describing: error), String(describing: RuntimeHealthWaitRunnerError.runtimeHealthFailed))
        }
        XCTAssertTrue(harness.events.contains {
            $0.contains("guest-log-sync-service-not-loaded")
        })
    }
}

private final class HealthWaitHarness {
    var snapshots: [RuntimeHealthSnapshot]
    var events: [String] = []
    var loadedServices = Set([
        RuntimeManagedService.vm,
        RuntimeManagedService.guestLogSync,
        RuntimeManagedService.proxy,
        RuntimeManagedService.watchdog,
    ])

    init(snapshots: [RuntimeHealthSnapshot]) {
        self.snapshots = snapshots
    }

    var runner: RuntimeHealthWaitRunner {
        RuntimeHealthWaitRunner(
            configuration: RuntimeHealthWaitWorkflowConfiguration(
                timeoutSeconds: 9.0,
                pollIntervalSeconds: 3.0,
                progressEveryAttempts: 5
            ),
            serviceStates: { services in
                Dictionary(uniqueKeysWithValues: services.map { service in
                    (service, self.loadedServices.contains(service) ? .loaded : .notLoaded)
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
            sleep: {
                self.events.append("sleep")
            },
            log: { message in
                self.events.append("log:\(message)")
            }
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
