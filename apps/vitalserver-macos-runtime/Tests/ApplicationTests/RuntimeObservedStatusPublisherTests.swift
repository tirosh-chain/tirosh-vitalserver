import Contracts
import Application
import XCTest

final class RuntimeObservedStatusPublisherTests: XCTestCase {
    func testPublishStatusWritesStatusWithoutProjectingReturnedVitalDBObservation() throws {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 30
        )
        var writeCalls = 0
        let publisher = RuntimeObservedStatusPublisher(
            writeStatus: { status in
                writeCalls += 1
                XCTAssertEqual(status, .healthy)
                return self.runtimeHealthSnapshot(vitalDBObservation: observation)
            }
        )

        try publisher.publishStatus(.healthy, operation: .health, message: "runtime healthy")

        XCTAssertEqual(writeCalls, 1)
    }

    private func runtimeHealthSnapshot(
        vitalDBObservation: VitalDBObservationDocument?
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
