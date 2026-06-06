import Application
import Contracts
import Workflow
import XCTest

final class RuntimeHealthRefreshWorkflowTests: XCTestCase {
    func testRefreshWritesHealthyStatus() throws {
        let harness = HealthRefreshHarness(snapshot: healthSnapshot(reasons: []))

        let decision = try harness.workflow.refresh()

        XCTAssertTrue(decision.healthy)
        XCTAssertEqual(harness.events, [
            "status:healthy:health:runtime health check passed",
        ])
    }

    func testRefreshWritesUnhealthyStatusAndEventBestEffortBeforeFailing() {
        let harness = HealthRefreshHarness(snapshot: healthSnapshot(reasons: [.auditProxyHTTP("failed")]))

        XCTAssertThrowsError(try harness.workflow.refresh()) { error in
            XCTAssertEqual(
                String(describing: error),
                "runtime health check failed: audit-proxy-http-failed"
            )
        }
        XCTAssertEqual(harness.events, [
            "best-effort-status:degraded:health:runtime health check failed: audit-proxy-http-failed",
            "best-effort-event:degraded:health:runtime domain errors observed: audit-proxy-http-failed",
        ])
    }
}

private final class HealthRefreshHarness {
    let snapshot: RuntimeHealthSnapshot
    var events: [String] = []

    init(snapshot: RuntimeHealthSnapshot) {
        self.snapshot = snapshot
    }

    var workflow: RuntimeHealthRefreshWorkflow {
        RuntimeHealthRefreshWorkflow(
            useCase: RefreshRuntimeHealthUseCase(
                ports: RuntimeHealthRefreshPorts(healthSnapshot: {
                    self.snapshot
                })
            ),
            writer: RuntimeHealthRefreshWriter(
                writeStatus: { status, operation, message in
                    self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
                },
                writeStatusBestEffort: { status, operation, message in
                    self.events.append("best-effort-status:\(status.rawValue):\(operation.rawValue):\(message)")
                },
                recordObservedEventBestEffort: { status, operation, message, _ in
                    self.events.append("best-effort-event:\(status.rawValue):\(operation.rawValue):\(message)")
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
