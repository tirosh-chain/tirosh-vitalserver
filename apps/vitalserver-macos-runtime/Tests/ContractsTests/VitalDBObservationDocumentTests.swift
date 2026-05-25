import Contracts
import XCTest

final class VitalDBObservationDocumentTests: XCTestCase {
    func testObservationDocumentRoundTripsThroughJSON() throws {
        let document = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_A",
                    ip: "10.0.0.10",
                    lastSeenAt: "2026-05-25T00:00:00Z",
                    version: "1.0.0",
                    info: "OR",
                    config: "{}",
                    online: true
                ),
            ],
            anomalies: [
                VitalDBAnomalyObservation(
                    id: "duplicate-ip-1",
                    kind: .duplicateIP,
                    severity: .critical,
                    observedAt: "2026-05-25T00:00:00Z",
                    subject: "10.0.0.10",
                    message: "duplicate-ip"
                ),
            ]
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(VitalDBObservationDocument.self, from: encoded)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.anomalies.first?.kind.rawValue, "duplicate-ip")
    }

    func testRuntimeEventTypeIncludesVitalDBObservationEvents() {
        XCTAssertEqual(RuntimeEventType(rawValue: "vitaldb-observed"), .vitalDBObserved)
        XCTAssertEqual(RuntimeEventType(rawValue: "vitaldb-observer-unhealthy"), .vitalDBObserverUnhealthy)
        XCTAssertEqual(RuntimeEventType(rawValue: "vitaldb-anomaly-detected"), .vitalDBAnomalyDetected)
    }
}
