import Contracts
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeEventDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeEventDisplayPolicy()

    func testEventItemOwnsAuditProxyDetailTextAndStatusSeverity() {
        let event = RuntimeEventDocument(
            id: "event-1",
            eventType: .auditProxyObserved,
            timestamp: "2026-05-24T01:00:00Z",
            product: "VitalServer Helper",
            status: .degraded,
            previousStatus: .healthy,
            operation: .watchdog,
            message: "audit proxy observed",
            runtimeVersion: "0.1.6",
            failureReasons: [],
            containerObservation: RuntimeContainerObservation(
                auditProxyHTTP: "200",
                auditProxyStatus: RuntimeAuditProxyStatusDocument(
                    activeRecorderConnections: 3,
                    recorders: [
                        RuntimeRecorderConnectionObservation(vrcode: "VR_A", activeConnections: 1),
                        RuntimeRecorderConnectionObservation(vrcode: "VR_B", activeConnections: 2),
                    ]
                ),
                containerLogsPresent: true,
                containerLogsBytes: 1
            ),
            progress: nil
        )

        let item = policy.item(for: event)

        XCTAssertEqual(item.id, "event-1")
        XCTAssertEqual(item.eventType, "audit-proxy-observed")
        XCTAssertEqual(item.status, "degraded")
        XCTAssertEqual(item.statusSeverity, .warning)
        XCTAssertEqual(item.operation, "watchdog")
        XCTAssertEqual(item.detailText, "Active recorder connections: 3, Known recorders: 2")
    }
}
