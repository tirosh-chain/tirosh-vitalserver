import Contracts
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeEventDisplayPolicyTests: XCTestCase {
    private let policy = RuntimeEventDisplayPolicy()

    func testEventItemOwnsRecorderIngressDetailTextAndStatusSeverity() {
        let event = RuntimeEventDocument(
            id: "event-1",
            eventType: .recorderIngressObserved,
            timestamp: "2026-05-24T01:00:00Z",
            product: "VitalServer Helper",
            status: .degraded,
            previousStatus: .healthy,
            operation: .watchdog,
            message: "recorder ingress observed",
            runtimeVersion: "0.1.6",
            vmState: .stale,
            vmErrors: [.runtimeStateStale],
            failureReasons: [],
            containerObservation: RuntimeContainerObservation(
                recorderIngressHTTP: "200",
                recorderIngressStatus: RuntimeRecorderIngressStatusDocument(
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
        XCTAssertEqual(item.eventType, "recorder-ingress-observed")
        XCTAssertEqual(item.status, "degraded")
        XCTAssertEqual(item.statusSeverity, .warning)
        XCTAssertEqual(item.operation, "watchdog")
        XCTAssertEqual(
            item.detailText,
            "VM state: Stale, VM errors: Guest runtime state stale, Active recorder connections: 3, Known recorders: 2"
        )
    }

    func testEventItemDisplaysDomainFailureReasonsWithRecoveryActions() {
        let event = RuntimeEventDocument(
            id: "event-2",
            eventType: .domainErrorObserved,
            timestamp: "2026-05-24T01:00:00Z",
            product: "VitalServer Helper",
            status: .degraded,
            previousStatus: .healthy,
            operation: .health,
            message: "runtime domain errors observed",
            runtimeVersion: "0.1.6",
            failureReasons: [.proxyPortInUse(port: 80, listeners: "nginx-1234")],
            progress: nil
        )

        let item = policy.item(for: event)

        XCTAssertEqual(item.eventType, "domain-error-observed")
        XCTAssertEqual(
            item.detailText,
            "Failure reasons: Host proxy port 80 in use by nginx-1234 (Free host proxy port)"
        )
    }

    func testEventItemAllowsCommandEventsWithoutRuntimeStatusContext() {
        let event = RuntimeEventDocument(
            id: "event-3",
            source: "host-command",
            eventType: .runtimeCommandStarted,
            timestamp: "2026-05-30T01:00:00Z",
            product: "VitalServer Helper",
            previousStatus: nil,
            message: "command started",
            runtimeVersion: "0.1.9",
            failureReasons: [],
            progress: nil
        )

        let item = policy.item(for: event)

        XCTAssertEqual(item.status, "Unknown")
        XCTAssertEqual(item.statusSeverity, .neutral)
        XCTAssertEqual(item.operation, "Unknown")
    }
}
