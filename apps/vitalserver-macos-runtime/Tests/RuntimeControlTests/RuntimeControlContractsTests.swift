import RuntimeControl
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
            vmServiceState: .loaded,
            proxyServiceState: .loaded,
            watchdogServiceState: .loaded,
            runtimeState: .healthy,
            operation: .applyBundle,
            readIssues: [RuntimeStatusReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout")],
            vmState: .running,
            vmErrors: [],
            vmIP: "192.168.64.2",
            guestHTTP: "200",
            hostProxyHTTP: "200"
        )

        XCTAssertTrue(RuntimeReadinessPolicy.isReady(status))

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeStatus.self, from: encoded)

        XCTAssertEqual(decoded.operation, .applyBundle)
        XCTAssertEqual(decoded.readIssues, [
            RuntimeStatusReadIssue(source: "hostProxyHTTP", message: "exitCode=28 stderr=timeout"),
        ])
        XCTAssertEqual(decoded.vmState, .running)
        XCTAssertEqual(decoded.vmErrors ?? [], [])
        XCTAssertEqual(decoded.vmServiceState, .loaded)
        XCTAssertEqual(decoded.proxyServiceState, .loaded)
        XCTAssertEqual(decoded.watchdogServiceState, .loaded)
        XCTAssertTrue(RuntimeReadinessPolicy.isReady(decoded))
    }

    func testRuntimeStatusIncludesDataDirectoryStats() throws {
        let status = RuntimeStatus(
            dataStorageError: "volume read failed",
            dataDirectoryStats: RuntimeDataDirectoryStats(fileCount: 2, sizeBytes: 1024)
        )

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeStatus.self, from: encoded)

        XCTAssertEqual(decoded.dataStorageError, "volume read failed")
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

    func testRuntimeEventHistoryIncludesOptionalReadMetadata() throws {
        let history = RuntimeEventHistory(
            events: [],
            nextCursor: "opaque-cursor",
            matchingCount: 3,
            readError: "sqlite=read failed"
        )

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeEventHistory.self, from: encoded)

        XCTAssertEqual(decoded.nextCursor, "opaque-cursor")
        XCTAssertEqual(decoded.matchingCount, 3)
        XCTAssertEqual(decoded.readError, "sqlite=read failed")
    }

    func testRuntimeCommandResultPreservesOutputIssuesAndDecodesLegacyPayload() throws {
        let result = RuntimeCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "",
            outputIssues: [
                RuntimeCommandOutputIssue(
                    stream: .stderr,
                    message: "command stderr is not valid UTF-8"
                ),
            ]
        )

        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(RuntimeCommandResult.self, from: encoded)
        let legacy = try JSONDecoder().decode(RuntimeCommandResult.self, from: Data("""
        {
          "exitCode": 0,
          "stdout": "ok",
          "stderr": ""
        }
        """.utf8))

        XCTAssertEqual(decoded.outputIssues, result.outputIssues)
        XCTAssertEqual(legacy.outputIssues, [])
    }

    func testRuntimeTestKitStatusPreservesReadIssuesAndDecodesLegacyPayload() throws {
        let status = RuntimeTestKitStatus(
            enabled: true,
            state: .failed,
            lastError: "TestKit failed",
            readIssues: [
                RuntimeTestKitReadIssue(source: "containerAPI", message: "read failed"),
            ]
        )

        let encoded = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeTestKitStatus.self, from: encoded)
        let legacy = try JSONDecoder().decode(RuntimeTestKitStatus.self, from: Data("""
        {
          "enabled": true,
          "state": "running",
          "sessions": [],
          "beds": []
        }
        """.utf8))

        XCTAssertEqual(decoded.readIssues, status.readIssues)
        XCTAssertEqual(legacy.readIssues, [])
    }

    func testVitalDBObservationSnapshotPreservesUnavailableState() throws {
        let snapshot = RuntimeVitalDBObservationSnapshot.unavailable(readError: "sqlite=read failed")

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RuntimeVitalDBObservationSnapshot.self, from: encoded)

        XCTAssertEqual(decoded.state, .unavailable)
        XCTAssertNil(decoded.observation)
        XCTAssertEqual(decoded.readError, "sqlite=read failed")
    }

    func testVitalDBObservationSnapshotFromOptionalPreservesLoadedReadError() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60
        )

        let snapshot = RuntimeVitalDBObservationSnapshot.fromOptional(
            observation,
            readError: "projection=read failed"
        )

        XCTAssertEqual(snapshot.state, .loaded)
        XCTAssertEqual(snapshot.observation?.observedAt, "2026-05-31T00:00:00Z")
        XCTAssertEqual(snapshot.readError, "projection=read failed")
    }

    func testVitalRelationshipHistoryPreservesReadError() throws {
        let history = RuntimeVitalRelationshipHistory(readError: "assignments=read failed")

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(RuntimeVitalRelationshipHistory.self, from: encoded)

        XCTAssertEqual(decoded.assignments, [])
        XCTAssertEqual(decoded.events, [])
        XCTAssertEqual(decoded.readError, "assignments=read failed")
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
        XCTAssertNil(history.recorders[0].activityTimeline)
        XCTAssertEqual(history.activityHistory.source, .notProvided)
        XCTAssertEqual(history.recorders[1].status, RuntimeVitalRecorderStatus.notObserved)
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
        XCTAssertEqual(history.beds[1].status, RuntimeVitalBedStatus.notObserved)
        XCTAssertEqual(history.beds[1].observationCount, 1)
        XCTAssertEqual(history.summary.knownRecorders, 2)
        XCTAssertEqual(history.summary.currentRecorders, 1)
        XCTAssertEqual(history.summary.onlineRecorders, 1)
        XCTAssertEqual(history.summary.staleRecorders, 0)
        XCTAssertEqual(history.summary.recorderAnomalies, 1)
        XCTAssertEqual(history.summary.knownBeds, 2)
        XCTAssertEqual(history.summary.onlineBeds, 1)
        XCTAssertEqual(history.summary.staleBeds, 0)
        XCTAssertEqual(history.summary.bedAssignments, 1)
        XCTAssertEqual(history.summary.bedAnomalies, 0)
    }

    func testVitalRecorderHistoryKeepsCurrentOfflineBedDistinctFromNotObserved() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:02:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-offline",
                    name: "OR Offline",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: false
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])

        XCTAssertEqual(history.beds.first?.status, RuntimeVitalBedStatus.offline)
    }

    func testVitalRecorderHistoryReportsCollapsedDuplicateSourceObservations() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:02:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_DUP",
                    ip: "192.168.64.10",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: true
                ),
                VitalDBRecorderObservation(
                    vrcode: "VR_DUP",
                    ip: "192.168.64.11",
                    lastSeenAt: "2026-05-26T00:01:10Z",
                    online: true
                ),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-dup",
                    name: "OR A",
                    lastSeenAt: "2026-05-26T00:01:00Z",
                    online: true
                ),
                VitalDBBedObservation(
                    bedID: "bed-dup",
                    name: "OR A duplicate",
                    lastSeenAt: "2026-05-26T00:01:10Z",
                    online: true
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])

        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_DUP"])
        XCTAssertEqual(history.recorders.first?.lastIP, "192.168.64.11")
        XCTAssertEqual(history.recorders.first?.duplicateObservationCount, 1)
        XCTAssertEqual(history.beds.map(\.bedID), ["bed-dup"])
        XCTAssertEqual(history.beds.first?.name, "OR A duplicate")
        XCTAssertEqual(history.beds.first?.duplicateObservationCount, 1)
    }

    func testVitalRecorderHistoryUsesProjectedActivityBucketsWhenProvided() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-26T00:02:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                .init(
                    vrcode: "VR_A",
                    ip: "192.168.64.12",
                    lastSeenAt: "2026-05-26T00:02:00Z",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 99,
                        byteCount: 99_000,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-26T00:02:00Z",
                                bucketSeconds: 60,
                                messageCount: 99,
                                byteCount: 99_000
                            ),
                        ]
                    )
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(
            observations: [observation],
            activityBuckets: [
                VitalDBRecorderActivityBucketRecord(
                    vrcode: "VR_A",
                    bucketStartedAt: "2026-05-26T00:01:00Z",
                    bucketSeconds: 60,
                    messageCount: 3,
                    byteCount: 900,
                    roomCount: 1,
                    firstObservedAt: "2026-05-26T00:01:05Z",
                    lastObservedAt: "2026-05-26T00:01:55Z"
                ),
            ]
        )

        let activity = history.recorders.first?.activityTimeline
        XCTAssertEqual(activity?.count, 1)
        XCTAssertEqual(activity?.first?.observedAt, "2026-05-26T00:01:55Z")
        XCTAssertEqual(activity?.first?.messageCount, 3)
        XCTAssertEqual(activity?.first?.byteCount, 900)
        XCTAssertEqual(activity?.first?.buckets.first?.bucketStartedAt, "2026-05-26T00:01:00Z")
        XCTAssertEqual(history.activityHistory.source, .sqliteProjection)
        XCTAssertEqual(history.activityHistory.bucketCount, 1)
        XCTAssertEqual(history.activityHistory.latestBucketStartedAt, "2026-05-26T00:01:00Z")
    }

    func testVitalRecorderHistoryOrdersTimestampsByInstantInsteadOfString() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_OFFSET",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-31T09:00:00+09:00",
                    online: true
                ),
                VitalDBRecorderObservation(
                    vrcode: "VR_UTC",
                    ip: "192.168.64.21",
                    lastSeenAt: "2026-05-31T00:00:01Z",
                    online: true
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])
        let summary = RuntimeVitalRecorderSummary(status: RuntimeStatus(vitalDBObservation: observation))

        XCTAssertEqual(history.recorders.map(\.vrcode), ["VR_UTC", "VR_OFFSET"])
        XCTAssertEqual(summary.latestRecorder?.vrcode, "VR_UTC")
    }

    func testVitalRecorderHistoryDoesNotInferLastSeenFromObservationTimestamp() {
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_NO_LAST_SEEN",
                    online: true
                ),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-no-last-seen",
                    vrcode: "VR_NO_LAST_SEEN",
                    online: true
                ),
            ]
        )

        let history = RuntimeVitalRecorderHistory(observations: [observation])

        XCTAssertNil(history.recorders.first?.firstSeenAt)
        XCTAssertNil(history.recorders.first?.lastSeenAt)
        XCTAssertNil(history.beds.first?.firstSeenAt)
        XCTAssertNil(history.beds.first?.lastSeenAt)
        XCTAssertEqual(history.recorders.first?.observationCount, 1)
        XCTAssertEqual(history.beds.first?.observationCount, 1)
    }

    func testVitalRecorderHistoryDoesNotPreservePreviousRecorderFieldsWhenLatestOmitsThem() {
        let firstObservation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_PARTIAL",
                    ip: "192.168.64.20",
                    lastSeenAt: "2026-05-31T00:00:00Z",
                    version: "1.0.0",
                    online: true
                ),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR A",
                    vrcode: "VR_PARTIAL",
                    patientConnected: true,
                    online: true
                ),
            ]
        )
        let latestObservation = VitalDBObservationDocument(
            observedAt: "2026-05-31T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_PARTIAL",
                    online: true
                ),
            ],
            beds: []
        )

        let recorder = RuntimeVitalRecorderHistory(
            observations: [firstObservation, latestObservation]
        ).recorders.first

        XCTAssertEqual(recorder?.presentInLatestObservation, true)
        XCTAssertNil(recorder?.lastIP)
        XCTAssertNil(recorder?.version)
        XCTAssertNil(recorder?.lastSeenAt)
        XCTAssertNil(recorder?.bedID)
        XCTAssertNil(recorder?.bedName)
        XCTAssertNil(recorder?.patientConnected)
    }

    func testVitalRecorderActivityPointRequiresCompletePayload() throws {
        let completePayload = """
        {
          "observedAt": "2026-05-26T00:01:55Z",
          "windowSeconds": 60,
          "messageCount": 3,
          "byteCount": 900,
          "roomCount": 1,
          "messagesPerSecond": 0.05,
          "bytesPerSecond": 15,
          "buckets": []
        }
        """

        let decoded = try JSONDecoder().decode(
            RuntimeVitalRecorderActivityPoint.self,
            from: Data(completePayload.utf8)
        )

        XCTAssertEqual(decoded.roomCount, 1)
        XCTAssertEqual(decoded.messagesPerSecond, 0.05)
        XCTAssertEqual(decoded.bytesPerSecond, 15)
        XCTAssertEqual(decoded.buckets, [])

        for missingField in ["roomCount", "messagesPerSecond", "bytesPerSecond", "buckets"] {
            XCTAssertThrowsError(try JSONDecoder().decode(
                RuntimeVitalRecorderActivityPoint.self,
                from: Data(activityPointPayload(missing: missingField).utf8)
            ), missingField)
        }
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

    func testVitalRecorderSummaryDoesNotInferRecorderStateFromAuditProxyConnections() {
        let status = RuntimeStatus(
            containerObservation: RuntimeContainerObservation(
                auditProxyHTTP: "200",
                auditProxyStatus: RuntimeAuditProxyStatusDocument(
                    activeRecorderConnections: 2,
                    recorders: [
                        RuntimeRecorderConnectionObservation(
                            vrcode: "VR_A",
                            activeConnections: 1,
                            selectedIp: "192.168.64.10",
                            lastSeenAt: "2026-05-26T00:01:00Z"
                        ),
                        RuntimeRecorderConnectionObservation(
                            vrcode: "VR_B",
                            activeConnections: 1,
                            selectedIp: "192.168.64.11",
                            lastSeenAt: "2026-05-26T00:01:30Z"
                        ),
                    ]
                ),
                containerLogsPresent: false,
                containerLogsBytes: nil
            )
        )

        let summary = RuntimeVitalRecorderSummary(status: status)

        XCTAssertEqual(summary.source, .unavailable)
        XCTAssertEqual(summary.activeConnections, 2)
        XCTAssertNil(summary.knownRecorders)
        XCTAssertNil(summary.onlineRecorders)
        XCTAssertNil(summary.staleRecorders)
        XCTAssertNil(summary.knownBeds)
        XCTAssertNil(summary.recorderAnomalies)
        XCTAssertNil(summary.observedAt)
        XCTAssertNil(summary.latestRecorder)
    }

    func testVitalRecorderSummaryDoesNotDefaultMissingAuditProxyConnectionsToZero() {
        let summary = RuntimeVitalRecorderSummary(status: RuntimeStatus())

        XCTAssertEqual(summary.source, .unavailable)
        XCTAssertNil(summary.activeConnections)
        XCTAssertNil(summary.knownRecorders)
    }
}

private func activityPointPayload(missing field: String) -> String {
    let fields: [(String, String)] = [
        ("observedAt", #""2026-05-26T00:01:55Z""#),
        ("windowSeconds", "60"),
        ("messageCount", "3"),
        ("byteCount", "900"),
        ("roomCount", "1"),
        ("messagesPerSecond", "0.05"),
        ("bytesPerSecond", "15"),
        ("buckets", "[]"),
    ]
    let body = fields
        .filter { $0.0 != field }
        .map { "\"\($0.0)\": \($0.1)" }
        .joined(separator: ",")
    return "{\(body)}"
}
