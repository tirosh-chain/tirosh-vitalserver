import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeEventFactoryTests: XCTestCase {
    func testObservedStatusEventCarriesHealthSnapshotContext() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 30
        )
        let snapshot = RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmErrors: [.missingIPAddress],
            vmIP: "192.168.64.2",
            proxyPort: 19090,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            vitalDBObservation: observation,
            failureReasons: [.guestHTTP("503")]
        )

        let event = factory().observedStatusEvent(
            status: .degraded,
            previousStatus: .healthy,
            operation: .watchdog,
            message: "watchdog observed degraded runtime",
            healthSnapshot: snapshot,
            eventType: .domainErrorObserved
        )

        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.timestamp, "2026-05-30T00:00:01Z")
        XCTAssertEqual(event.product, "VitalServerHelper")
        XCTAssertEqual(event.runtimeVersion, "1.2.3")
        XCTAssertEqual(event.status, .degraded)
        XCTAssertEqual(event.previousStatus, .healthy)
        XCTAssertEqual(event.operation, .watchdog)
        XCTAssertEqual(event.eventType, .domainErrorObserved)
        XCTAssertEqual(event.vmState, .running)
        XCTAssertEqual(event.vmErrors, [.missingIPAddress])
        XCTAssertEqual(event.failureReasons, [.guestHTTP("503")])
        XCTAssertEqual(event.vitalDBObservation, observation)
    }

    func testDocumentEventUsesExplicitTimestampAndSource() {
        let event = factory().documentEvent(
            source: "host-command",
            eventType: .runtimeCommandCompleted,
            timestamp: "2026-05-30T00:00:02Z",
            operation: .repairProxy,
            message: "command completed"
        )

        XCTAssertEqual(event.id, "event-1")
        XCTAssertEqual(event.source, "host-command")
        XCTAssertEqual(event.timestamp, "2026-05-30T00:00:02Z")
        XCTAssertEqual(event.product, "VitalServerHelper")
        XCTAssertEqual(event.runtimeVersion, "1.2.3")
        XCTAssertEqual(event.eventType, .runtimeCommandCompleted)
        XCTAssertEqual(event.operation, .repairProxy)
        XCTAssertEqual(event.failureReasons, [])
    }

    private func factory() -> RuntimeEventFactory {
        RuntimeEventFactory(
            id: { "event-1" },
            timestamp: { "2026-05-30T00:00:01Z" },
            product: "VitalServerHelper",
            runtimeVersion: { "1.2.3" }
        )
    }
}
