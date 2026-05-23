import RuntimeCore
import RuntimeContracts
@testable import HostRuntimeControl
import XCTest

final class RuntimeHealthCheckRunnerTests: XCTestCase {
    func testRunWritesHealthyStatusWhenSnapshotIsHealthy() throws {
        let harness = HealthCheckHarness(snapshot: healthSnapshot(reasons: []))

        try harness.runner.run()

        XCTAssertEqual(harness.events, [
            "print-status",
            "status:healthy:health:runtime health check passed",
            "print:health: ok",
        ])
    }

    func testRunWritesDegradedStatusAndThrowsWhenSnapshotIsUnhealthy() {
        let harness = HealthCheckHarness(snapshot: healthSnapshot(reasons: [.vmService("not-loaded")]))

        XCTAssertThrowsError(try harness.runner.run()) { error in
            XCTAssertEqual(String(describing: error), String(describing: LauncherError.runtimeHealthFailed))
        }
        XCTAssertEqual(harness.events, [
            "print-status",
            "status:degraded:health:runtime health check failed: vm-service-not-loaded",
            "print:health: failed",
        ])
    }
}

private final class HealthCheckHarness {
    let snapshot: RuntimeHealthSnapshot
    var events: [String] = []

    init(snapshot: RuntimeHealthSnapshot) {
        self.snapshot = snapshot
    }

    var runner: RuntimeHealthCheckRunner {
        RuntimeHealthCheckRunner(
            printStatus: {
                self.events.append("print-status")
            },
            healthSnapshot: {
                self.snapshot
            },
            writeStatus: { status, operation, message in
                self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            reasonText: { reasons in
                reasons.map(\.rawValue).joined(separator: ",")
            },
            printLine: { line in
                self.events.append("print:\(line)")
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
