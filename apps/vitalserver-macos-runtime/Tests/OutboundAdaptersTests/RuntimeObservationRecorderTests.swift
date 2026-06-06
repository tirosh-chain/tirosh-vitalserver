import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

final class RuntimeObservationRecorderTests: XCTestCase {
    func testRecordWritesEventOnly() throws {
        let harness = ObservationRecorderHarness()
        let event = runtimeEvent(vitalDBObservation: vitalDBObservation())

        try harness.recorder.recordEvent(event)

        XCTAssertEqual(harness.eventRepository.events, [event])
        XCTAssertTrue(harness.logs.isEmpty)
    }

    func testRecordPropagatesEventWriteFailure() {
        let harness = ObservationRecorderHarness()
        harness.eventRepository.appendError = ObservationRecorderError.eventAppend

        XCTAssertThrowsError(try harness.recorder.recordEvent(runtimeEvent(vitalDBObservation: vitalDBObservation())))
        XCTAssertTrue(harness.eventRepository.events.isEmpty)
    }
}

private final class ObservationRecorderHarness {
    let eventRepository = InMemoryRuntimeEventRepository()
    var logs: [String] = []

    var recorder: RuntimeObservationRecorder {
        RuntimeObservationRecorder(
            eventRepository: eventRepository,
            log: { message in
                self.logs.append(message)
            }
        )
    }
}

private final class InMemoryRuntimeEventRepository: RuntimeEventRecording {
    var events: [RuntimeEventDocument] = []
    var appendError: Error?

    func append(_ event: RuntimeEventDocument) throws {
        if let appendError {
            throw appendError
        }
        events.append(event)
    }
}

private func runtimeEvent(vitalDBObservation: VitalDBObservationDocument?) -> RuntimeEventDocument {
    RuntimeEventDocument(
        id: "event-1",
        eventType: .vitalDBObserved,
        timestamp: "2026-05-30T00:00:01Z",
        product: "ai.tirosh.vitalserver.helper",
        status: .healthy,
        previousStatus: .healthy,
        operation: .health,
        message: "vitaldb observed",
        runtimeVersion: "0.1.9",
        failureReasons: [],
        vitalDBObservation: vitalDBObservation,
        progress: nil
    )
}

private func vitalDBObservation() -> VitalDBObservationDocument {
    VitalDBObservationDocument(
        observedAt: "2026-05-30T00:00:00Z",
        ready: true,
        recorderOnlineThresholdSeconds: 30,
        recorders: [
            VitalDBRecorderObservation(
                vrcode: "VR_TEST",
                ip: "10.200.10.10",
                online: true
            ),
        ]
    )
}

private enum ObservationRecorderError: Error {
    case eventAppend
}
