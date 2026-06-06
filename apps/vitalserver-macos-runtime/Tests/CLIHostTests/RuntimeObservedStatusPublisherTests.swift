import Contracts
import Workflow
import XCTest
import Errors
@testable import CLIHost

final class RuntimeObservedStatusPublisherTests: XCTestCase {
    func testPublishStatusProjectsReturnedVitalDBObservation() throws {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 30
        )
        var projected: [VitalDBObservationDocument] = []
        let publisher = RuntimeObservedStatusPublisher(
            writeStatus: { status, operation, message, progress in
                XCTAssertEqual(status, .healthy)
                XCTAssertEqual(operation, .health)
                XCTAssertEqual(message, "runtime healthy")
                XCTAssertNil(progress)
                return self.runtimeHealthSnapshot(vitalDBObservation: observation)
            },
            projectObservation: { projected.append($0) }
        )

        try publisher.publishStatus(.healthy, operation: .health, message: "runtime healthy")

        XCTAssertEqual(projected, [observation])
    }

    func testPublishStatusDoesNotProjectWhenSnapshotHasNoVitalDBObservation() throws {
        var projected: [VitalDBObservationDocument] = []
        let publisher = RuntimeObservedStatusPublisher(
            writeStatus: { _, _, _, _ in self.runtimeHealthSnapshot(vitalDBObservation: nil) },
            projectObservation: { projected.append($0) }
        )

        try publisher.publishStatus(.degraded, operation: .watchdog, message: "runtime degraded")

        XCTAssertTrue(projected.isEmpty)
    }

    private func runtimeHealthSnapshot(
        vitalDBObservation: VitalDBObservationDocument?
    ) -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmIP: "192.168.64.2",
            proxyPort: 19090,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            vitalDBObservation: vitalDBObservation,
            failureReasons: []
        )
    }
}
