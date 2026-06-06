import Contracts
import OutboundAdapters
import XCTest
import Errors

final class RuntimeVitalDBObservationProjectorTests: XCTestCase {
    func testProjectAppendsObservation() throws {
        let observation = vitalDBProjectorObservation()
        var appended: [VitalDBObservationDocument] = []
        let projector = RuntimeVitalDBObservationProjector(
            appendObservation: { appended.append($0) },
            log: { _ in XCTFail("unexpected log") }
        )

        try projector.project(observation)

        XCTAssertEqual(appended, [observation])
    }

    func testProjectPropagatesAppendFailure() {
        let projector = RuntimeVitalDBObservationProjector(
            appendObservation: { _ in throw RuntimeVitalDBObservationProjectorTestError.appendFailed },
            log: { _ in XCTFail("unexpected log") }
        )

        XCTAssertThrowsError(try projector.project(vitalDBProjectorObservation())) { error in
            XCTAssertEqual(error as? RuntimeVitalDBObservationProjectorTestError, .appendFailed)
        }
    }

    func testProjectBestEffortLogsAppendFailure() {
        var logs: [String] = []
        let projector = RuntimeVitalDBObservationProjector(
            appendObservation: { _ in
                throw NSError(domain: "RuntimeVitalDBObservationProjectorTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "append failed",
                ])
            },
            log: { logs.append($0) }
        )

        projector.projectBestEffort(vitalDBProjectorObservation())

        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("vitaldb observation projection failed"))
        XCTAssertTrue(logs[0].contains("observedAt=2026-05-30T00:00:00Z"))
        XCTAssertTrue(logs[0].contains("append failed"))
    }
}

private enum RuntimeVitalDBObservationProjectorTestError: Error {
    case appendFailed
}

private func vitalDBProjectorObservation() -> VitalDBObservationDocument {
    VitalDBObservationDocument(
        observedAt: "2026-05-30T00:00:00Z",
        ready: true,
        recorderOnlineThresholdSeconds: 30,
        recorders: [
            VitalDBRecorderObservation(vrcode: "VR_TEST", ip: "10.200.10.10", online: true),
        ]
    )
}
