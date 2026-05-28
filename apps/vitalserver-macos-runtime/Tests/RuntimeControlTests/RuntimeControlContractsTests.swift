import RuntimeControl
import Core
import Contracts
import XCTest

final class RuntimeControlContractsTests: XCTestCase {
    func testRuntimeStatePreservesUnknownValues() throws {
        let state = RuntimeState(rawValue: "maintenance")

        XCTAssertEqual(state.rawValue, "maintenance")

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeState.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("maintenance"))
    }

    func testRuntimeStatusUsesTypedOperationAndRoundTripsThroughJSON() throws {
        let status = RuntimeStatus(
            runtimeInstalled: true,
            vmServiceLoaded: true,
            proxyServiceLoaded: true,
            watchdogServiceLoaded: true,
            runtimeState: .healthy,
            operation: .applyBundle,
            vmState: .running,
            vmErrors: [],
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        XCTAssertTrue(status.isReady)

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeStatus.self, from: encoded)

        XCTAssertEqual(decoded.operation, .applyBundle)
        XCTAssertEqual(decoded.vmState, .running)
        XCTAssertEqual(decoded.vmErrors ?? [], [])
        XCTAssertTrue(decoded.isReady)
    }

    func testRuntimeStatusIncludesDataDirectoryStats() throws {
        let status = RuntimeStatus(
            dataDirectoryStats: RuntimeDataDirectoryStats(fileCount: 2, sizeBytes: 1024)
        )

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeStatus.self, from: encoded)

        XCTAssertEqual(decoded.dataDirectoryStats?.fileCount, 2)
        XCTAssertEqual(decoded.dataDirectoryStats?.sizeBytes, 1024)
    }

    func testRuntimeEventCursorWireCodecRoundTripsOpaqueCursor() {
        let cursor = RuntimeEventCursor(timestamp: "2026-05-24T00:01:00Z", id: "event-2")

        let encoded = RuntimeEventCursorWireCodec.encode(cursor)
        let decoded = RuntimeEventCursorWireCodec.decode(encoded)

        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(decoded, cursor)
    }

    func testRuntimeEventHistoryIncludesOptionalNextCursor() throws {
        let history = RuntimeEventHistory(events: [], nextCursor: "opaque-cursor")

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeEventHistory.self, from: encoded)

        XCTAssertEqual(decoded.nextCursor, "opaque-cursor")
    }

    func testVitalRecorderHistoryAggregatesByVrcode() {
        let firstObservation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.10",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    version: "1.0.0",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 2,
                        byteCount: 1024,
                        roomCount: 1,
                        messagesPerSecond: 0.01,
                        bytesPerSecond: 3.4,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-26T00:00:00Z",
                                bucketSeconds: 60,
                                messageCount: 2,
                                byteCount: 1024,
                                roomCount: 1
                            ),
                        ]
                    )
                ),
                .init(
                    vrcode: "VR_B",
                    ip: "192.168.64.11",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: true
                ),
            ],
            beds: [
                .init(bedID: "bed-a", name: "OR A", vrcode: "VR_A", patientConnected: true, online: true),
                .init(bedID: "bed-b", name: "OR B", vrcode: "VR_B", patientConnected: false, online: true),
            ]
        )
        let latestObservation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.12",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    version: "1.0.1",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 4,
                        byteCount: 2048,
                        roomCount: 2,
                        messagesPerSecond: 0.02,
                        bytesPerSecond: 6.8,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-26T00:01:00Z",
                                bucketSeconds: 60,
                                messageCount: 4,
                                byteCount: 2048,
                                roomCount: 2
                            ),
                        ]
                    )
                ),
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.9",
                    lastSeenAt: "2026-05-26T00:00:30Z",
                    version: "1.0.0",
                    online: true
                ),
            ],
            beds: [
                .init(bedID: "bed-a", name: "OR A Updated", vrcode: "VR_A", patientConnected: false, online: true),
            ],
            anomalies: [
                VitalDBAnomalyObservation(
                    id: "anomaly-a",
                    kind: .staleRecorder,
                    severity: VitalDBAnomalySeverity.warning,
                    observedAt: "2026-05-26T00:01:00Z",
                    subject: "VR_A",
                    message: "Recorder latency is above threshold."
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [latestObservation, firstObservation])

        XCTAssertEqual(history.updatedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.recorders.map { $0.vrcode }, ["VR_A", "VR_B"])
        XCTAssertEqual(history.recorders[0].status, RuntimeVitalRecorderStatus.online)
        XCTAssertEqual(history.recorders[0].lastIP, "192.168.64.12")
        XCTAssertEqual(history.recorders[0].version, "1.0.1")
        XCTAssertEqual(history.recorders[0].bedName, "OR A Updated")
        XCTAssertEqual(history.recorders[0].patientConnected, false)
        XCTAssertEqual(history.recorders[0].observationCount, 2)
        XCTAssertEqual(history.recorders[0].presentInLatestObservation, true)
        XCTAssertEqual(history.recorders[0].currentAnomalyCount, 1)
        XCTAssertEqual(history.recorders[0].latestAnomalySeverity, VitalDBAnomalySeverity.warning)
        XCTAssertEqual(history.recorders[0].activityTimeline.map(\.observedAt), [
            "2026-05-26T00:00:00Z",
            "2026-05-26T00:01:00Z",
        ])
        XCTAssertEqual(history.recorders[0].activityTimeline.last?.byteCount, 2048)
        XCTAssertEqual(history.recorders[0].activityTimeline.last?.bytesPerSecond, 6.8)
        XCTAssertEqual(history.recorders[0].activityTimeline.last?.buckets.first?.messageCount, 4)
        XCTAssertEqual(history.recorders[1].status, RuntimeVitalRecorderStatus.offline)
        XCTAssertEqual(history.recorders[1].bedName, "OR B")
        XCTAssertEqual(history.recorders[1].observationCount, 1)
        XCTAssertEqual(history.recorders[1].presentInLatestObservation, false)
        XCTAssertEqual(history.beds.map(\.bedID), ["bed-a", "bed-b"])
        XCTAssertEqual(history.beds[0].name, "OR A Updated")
        XCTAssertEqual(history.beds[0].vrcode, "VR_A")
        XCTAssertEqual(history.beds[0].status, RuntimeVitalBedStatus.online)
        XCTAssertEqual(history.beds[0].patientConnected, false)
        XCTAssertEqual(history.beds[0].observationCount, 2)
        XCTAssertEqual(history.beds[1].name, "OR B")
        XCTAssertEqual(history.beds[1].status, RuntimeVitalBedStatus.offline)
        XCTAssertEqual(history.beds[1].observationCount, 1)
    }

    func testVitalRecorderSummaryCountsUniqueVrcodes() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.10",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: true
                ),
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.11",
                    lastSeenAt: "2026-05-26T00:00:30Z",
                    online: true
                ),
                .init(
                    vrcode: "VR_B",
                    ip: "192.168.64.12",
                    lastSeenAt: "2026-05-26T00:00:00Z",
                    online: false,
                    stale: true
                ),
            ]
        )

        let summary = RuntimeVitalRecorderSummary(status: RuntimeStatus(vitalDBObservation: observation))

        XCTAssertEqual(summary.knownRecorders, 2)
        XCTAssertEqual(summary.onlineRecorders, 1)
        XCTAssertEqual(summary.staleRecorders, 1)
        XCTAssertEqual(summary.latestRecorder?.vrcode, "VR_A")
        XCTAssertEqual(summary.latestRecorder?.ip, "192.168.64.10")
    }
}
