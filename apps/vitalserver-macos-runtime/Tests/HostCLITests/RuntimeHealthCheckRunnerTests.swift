import Core
import Contracts
@testable import HostCLI
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
            "event:degraded:health:runtime VM errors observed: vm-service-state-not-loaded",
            "print:health: failed",
        ])
    }

    func testRunRecordsDomainErrorEventWhenUnhealthyReasonIsNotVMError() {
        let harness = HealthCheckHarness(snapshot: healthSnapshot(reasons: [.auditProxyHTTP("failed")]))

        XCTAssertThrowsError(try harness.runner.run())

        XCTAssertEqual(harness.events, [
            "print-status",
            "status:degraded:health:runtime health check failed: audit-proxy-http-failed",
            "event:degraded:health:runtime domain errors observed: audit-proxy-http-failed",
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
            recordObservedEvent: { status, operation, message, _ in
                self.events.append("event:\(status.rawValue):\(operation.rawValue):\(message)")
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
        vmState: reasons.isEmpty ? .running : .unreachable,
        vmErrors: reasons.compactMap { reason in
            if case .vmService(let state) = reason {
                return .serviceNotLoaded(state)
            }
            return nil
        },
        vmIP: "192.168.64.2",
        proxyPort: 18080,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: reasons
    )
}
