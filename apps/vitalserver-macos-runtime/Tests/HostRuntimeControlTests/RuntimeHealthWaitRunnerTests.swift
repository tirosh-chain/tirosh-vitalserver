import RuntimeCore
import RuntimeContracts
@testable import HostRuntimeControl
import XCTest

final class RuntimeHealthWaitRunnerTests: XCTestCase {
    func testWaitSkipsWhenNoServiceRestarted() throws {
        let harness = HealthWaitHarness(snapshots: [healthSnapshot(reasons: [])])

        try harness.runner.wait(for: RuntimeServiceRestartPolicy(
            restartVM: false,
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
            restartProxy: false,
            restartWatchdog: false
        ))) { error in
            XCTAssertEqual(String(describing: error), String(describing: LauncherError.runtimeHealthFailed))
        }
        XCTAssertTrue(harness.events.contains("log:runtime health failed early reason=guest-bootstrap-failed"))
    }
}

private final class HealthWaitHarness {
    var snapshots: [RuntimeHealthSnapshot]
    var events: [String] = []
    var loadedServices = Set([
        RuntimeManagedService.vm,
        RuntimeManagedService.proxy,
        RuntimeManagedService.watchdog,
    ])

    init(snapshots: [RuntimeHealthSnapshot]) {
        self.snapshots = snapshots
    }

    var runner: RuntimeHealthWaitRunner {
        RuntimeHealthWaitRunner(
            isLaunchdLoaded: { service in
                self.loadedServices.contains(service)
            },
            healthSnapshot: {
                if self.snapshots.count > 1 {
                    return self.snapshots.removeFirst()
                }
                return self.snapshots[0]
            },
            writeStatus: { status, operation, message in
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
        vmIP: "192.168.64.2",
        proxyPort: 18080,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}
