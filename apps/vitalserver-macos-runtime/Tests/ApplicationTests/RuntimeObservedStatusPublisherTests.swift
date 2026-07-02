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
            writeStatus: { status, operation, message, progress in
                writeCalls += 1
                XCTAssertEqual(status, .healthy)
                XCTAssertEqual(operation, .health)
                XCTAssertEqual(message, "runtime healthy")
                XCTAssertNil(progress)
                return self.runtimeHealthSnapshot(vitalDBObservation: observation)
            }
        )

        try publisher.publishStatus(.healthy, operation: .health, message: "runtime healthy")

        XCTAssertEqual(writeCalls, 1)
    }

    func testPublishStatusPassesProgressToWriter() throws {
        let progress = RuntimeProgressDocument(
            operation: .watchdog,
            phase: .running,
            step: .startRuntimeServices,
            stepStatus: .started,
            message: "checking runtime",
            reasonCodes: [],
            startedAt: nil,
            updatedAt: "2026-07-01T00:00:00Z"
        )
        var receivedProgress: RuntimeProgressDocument?
        let publisher = RuntimeObservedStatusPublisher(
            writeStatus: { _, _, _, progress in
                receivedProgress = progress
                return self.runtimeHealthSnapshot(vitalDBObservation: nil)
            }
        )

        try publisher.publishStatus(
            .degraded,
            operation: .watchdog,
            message: "runtime degraded",
            progress: progress
        )

        XCTAssertEqual(receivedProgress, progress)
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
