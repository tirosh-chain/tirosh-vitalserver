import Contracts
import Application
import XCTest
import Errors

final class RuntimeObservedEventPublisherTests: XCTestCase {
    func testRecordObservedEventUsesPreviousStatusAndInjectedEventTypePolicy() throws {
        var recorded: RecordedObservedEvent?
        var eventTypePolicyInputs: [(RuntimeHealthSnapshot, RuntimeEventType)] = []
        let publisher = RuntimeObservedEventPublisher(
            previousStatus: { .healthy },
            recordEvent: { status, previousStatus, operation, message, snapshot, eventType in
                recorded = RecordedObservedEvent(
                    status: status,
                    previousStatus: previousStatus,
                    operation: operation,
                    message: message,
                    snapshot: snapshot,
                    eventType: eventType
                )
            },
            recordEventBestEffort: { _, _, _, _, _, _ in
                XCTFail("best effort recorder should not be used")
            },
            eventTypeForSnapshot: { snapshot, defaultEventType in
                eventTypePolicyInputs.append((snapshot, defaultEventType))
                return .domainErrorObserved
            }
        )
        let snapshot = runtimeHealthSnapshot(failureReasons: [.guestHTTP("503")])

        try publisher.recordObservedEvent(
            .degraded,
            operation: .health,
            message: "health failed",
            snapshot: snapshot,
            defaultEventType: .healthObserved
        )

        XCTAssertEqual(recorded?.status, .degraded)
        XCTAssertEqual(recorded?.previousStatus, .healthy)
        XCTAssertEqual(recorded?.operation, .health)
        XCTAssertEqual(recorded?.message, "health failed")
        XCTAssertEqual(recorded?.snapshot, snapshot)
        XCTAssertEqual(recorded?.eventType, .domainErrorObserved)
        XCTAssertEqual(eventTypePolicyInputs.count, 1)
        XCTAssertEqual(eventTypePolicyInputs.first?.0, snapshot)
        XCTAssertEqual(eventTypePolicyInputs.first?.1, .healthObserved)
    }

    func testRecordObservedEventBestEffortCanUseExplicitEventType() {
        var recorded: RecordedObservedEvent?
        let publisher = RuntimeObservedEventPublisher(
            previousStatus: { .recovering },
            recordEvent: { _, _, _, _, _, _ in
                XCTFail("throwing recorder should not be used")
            },
            recordEventBestEffort: { status, previousStatus, operation, message, snapshot, eventType in
                recorded = RecordedObservedEvent(
                    status: status,
                    previousStatus: previousStatus,
                    operation: operation,
                    message: message,
                    snapshot: snapshot,
                    eventType: eventType
                )
            }
        )
        let snapshot = runtimeHealthSnapshot(vmErrors: [.missingIPAddress])

        publisher.recordObservedEventBestEffort(
            .recovering,
            operation: .watchdog,
            message: "recovery planned",
            snapshot: snapshot,
            eventType: .recoveryPlanned
        )

        XCTAssertEqual(recorded?.status, .recovering)
        XCTAssertEqual(recorded?.previousStatus, .recovering)
        XCTAssertEqual(recorded?.operation, .watchdog)
        XCTAssertEqual(recorded?.eventType, .recoveryPlanned)
        XCTAssertEqual(recorded?.snapshot, snapshot)
    }
}

private struct RecordedObservedEvent {
    let status: RuntimeStatusLevel
    let previousStatus: RuntimeStatusLevel?
    let operation: RuntimeOperation
    let message: String
    let snapshot: RuntimeHealthSnapshot
    let eventType: RuntimeEventType
}

private func runtimeHealthSnapshot(
    vmErrors: [RuntimeVMError] = [],
    failureReasons: [RuntimeFailureReason] = []
) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: .executable,
        proxyExecutable: .executable,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmState: .running,
        vmErrors: vmErrors,
        vmIP: "192.168.64.2",
        proxyPort: 19090,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: failureReasons
    )
}
