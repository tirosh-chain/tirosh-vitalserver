import Contracts
import XCTest
import Errors

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
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 12,
                        byteCount: 4096,
                        roomCount: 4,
                        firstSeenAt: "2026-05-25T00:00:01Z",
                        lastSeenAt: "2026-05-25T00:00:10Z",
                        messagesPerSecond: 0.04,
                        bytesPerSecond: 13.7,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-25T00:00:00Z",
                                bucketSeconds: 60,
                                messageCount: 12,
                                byteCount: 4096,
                                roomCount: 4
                            ),
                        ]
                    )
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
            ],
            readIssues: [
                VitalDBObservationReadIssue(
                    source: "proxyAccessLog",
                    message: "proxy access log is not valid UTF-8"
                ),
            ]
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(VitalDBObservationDocument.self, from: encoded)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.recorders.first?.activity?.byteCount, 4096)
        XCTAssertEqual(decoded.recorders.first?.activity?.buckets.first?.messageCount, 12)
        XCTAssertEqual(decoded.anomalies.first?.kind.rawValue, "duplicate-ip")
        XCTAssertEqual(decoded.readIssues, document.readIssues)
    }

    func testObservationDocumentDecodesLegacyPayloadWithoutReadIssues() throws {
        let payload = """
        {
          "schemaVersion": 1,
          "source": "vitaldb-observer",
          "observedAt": "2026-05-25T00:00:00Z",
          "ready": true,
          "recorderOnlineThresholdSeconds": 120,
          "recorders": [],
          "beds": [],
          "devices": [],
          "filters": [],
          "proxyConnections": [],
          "anomalies": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(VitalDBObservationDocument.self, from: payload)

        XCTAssertEqual(decoded.readIssues, [])
    }

    func testRuntimeEventTypeIncludesVitalDBObservationEvents() {
        XCTAssertEqual(RuntimeEventType(rawValue: "vitaldb-observed"), .vitalDBObserved)
        XCTAssertEqual(RuntimeEventType(rawValue: "vitaldb-observer-unhealthy"), .vitalDBObserverUnhealthy)
        XCTAssertEqual(RuntimeEventType(rawValue: "vitaldb-anomaly-detected"), .vitalDBAnomalyDetected)
    }

    func testRecorderActivityBucketQueryClampsLimitAndPreservesFilters() {
        let query = VitalDBRecorderActivityBucketQuery(
            vrcode: "VR_A",
            since: "2026-05-25T00:00:00Z",
            until: "2026-05-25T00:10:00Z",
            limit: 100_000
        )

        XCTAssertEqual(query.vrcode, "VR_A")
        XCTAssertEqual(query.since, "2026-05-25T00:00:00Z")
        XCTAssertEqual(query.until, "2026-05-25T00:10:00Z")
        XCTAssertEqual(query.limit, 50_000)
        XCTAssertEqual(VitalDBRecorderActivityBucketQuery(vrcode: "", limit: -1).vrcode, nil)
        XCTAssertEqual(VitalDBRecorderActivityBucketQuery(limit: -1).limit, 0)
    }
}
