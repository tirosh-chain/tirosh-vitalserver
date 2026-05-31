import Contracts
import Core
import Foundation
import HostInfrastructure
import XCTest

final class SQLiteRuntimeObservabilityStoreTests: XCTestCase {
    func testAppendsAndReadsRuntimeEventsByRecency() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try harness.store.append(event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .auditProxyObserved))
        try harness.store.append(event(id: "event-3", timestamp: "2026-05-24T00:02:00Z", type: .containerObserved))

        XCTAssertEqual(harness.store.recent(limit: 2).map(\.id), ["event-2", "event-3"])
    }

    func testQueriesRuntimeEventsByTypeAndTimestamp() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try harness.store.append(event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .auditProxyObserved))
        try harness.store.append(event(id: "event-3", timestamp: "2026-05-24T00:02:00Z", type: .auditProxyObserved))

        let events = harness.store.recent(
            limit: 10,
            eventType: .auditProxyObserved,
            since: "2026-05-24T00:02:00Z"
        )

        XCTAssertEqual(events.map(\.id), ["event-3"])
    }

    func testQueriesRuntimeEventsWithCursor() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try harness.store.append(event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .auditProxyObserved))
        try harness.store.append(event(id: "event-3", timestamp: "2026-05-24T00:02:00Z", type: .containerObserved))

        let firstPage = harness.store.query(RuntimeEventQuery(limit: 2))
        let secondPage = harness.store.query(RuntimeEventQuery(limit: 2, before: firstPage.nextCursor))

        XCTAssertEqual(firstPage.events.map(\.id), ["event-2", "event-3"])
        XCTAssertEqual(firstPage.nextCursor, RuntimeEventCursor(timestamp: "2026-05-24T00:01:00Z", id: "event-2"))
        XCTAssertEqual(secondPage.events.map(\.id), ["event-1"])
        XCTAssertNil(secondPage.nextCursor)
    }

    func testRuntimeEventQueryCarriesReadErrorWhenSQLiteIsUnavailable() throws {
        let store = SQLiteRuntimeObservabilityStore(url: URL(fileURLWithPath: "/dev/null/events.sqlite"))

        let page = store.query(RuntimeEventQuery(limit: 10))

        XCTAssertEqual(page.events, [])
        XCTAssertNotNil(page.readError)
    }

    func testProjectionCatchUpPopulatesSQLiteFromJSONLWhenSQLiteIsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let catchUp = RuntimeEventSQLiteProjectionCatchUp(
            primary: jsonl,
            secondary: sqlite,
            intervalSeconds: 0
        )
        let repository = CompositeRuntimeEventRepository(primary: jsonl, secondary: sqlite)

        try jsonl.append(event(id: "jsonl-event", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))

        catchUp.catchUpIfDue()

        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["jsonl-event"])
        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["jsonl-event"])
    }

    func testCompositeRepositoryReadsSQLiteWhenAvailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let repository = CompositeRuntimeEventRepository(primary: jsonl, secondary: sqlite)

        try repository.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))

        XCTAssertEqual(repository.recent(limit: 10).map(\.id), ["event-1"])
    }

    func testCompositeRepositoryLogsSecondaryAppendFailureWithoutLosingPrimaryEvent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqliteURL = directory.appendingPathComponent("events.sqlite")
        try Data("not a sqlite database".utf8).write(to: sqliteURL)
        let sqlite = SQLiteRuntimeEventRepository(url: sqliteURL)
        var logs: [String] = []
        let repository = CompositeRuntimeEventRepository(
            primary: jsonl,
            secondary: sqlite,
            log: { logs.append($0) }
        )

        try repository.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))

        XCTAssertEqual(jsonl.recent(limit: 10).map(\.id), ["event-1"])
        XCTAssertTrue(logs.contains { $0.contains("runtime event sqlite append failed eventID=event-1") })
    }

    func testCompositeRepositoryDoesNotCatchUpSQLiteDuringQuery() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let repository = CompositeRuntimeEventRepository(primary: jsonl, secondary: sqlite)

        try jsonl.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))

        XCTAssertEqual(repository.recent(limit: 10), [])
        XCTAssertEqual(sqlite.recent(limit: 10), [])
    }

    func testProjectionCatchUpHonorsIntervalWhenSQLiteIndexIsStale() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        let baseDate = Date(timeIntervalSince1970: 1_779_552_000)

        let first = event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged)
        let second = event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .containerObserved)
        try jsonl.append(first)
        try jsonl.append(second)
        try sqlite.append(first)
        try sqlite.markCaughtUp(at: baseDate)

        let notDueCatchUp = RuntimeEventSQLiteProjectionCatchUp(
            primary: jsonl,
            secondary: sqlite,
            intervalSeconds: 30,
            now: { baseDate.addingTimeInterval(10) }
        )
        notDueCatchUp.catchUpIfDue()
        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["event-1"])

        let dueCatchUp = RuntimeEventSQLiteProjectionCatchUp(
            primary: jsonl,
            secondary: sqlite,
            intervalSeconds: 30,
            now: { baseDate.addingTimeInterval(31) }
        )
        dueCatchUp.catchUpIfDue()
        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["event-1", "event-2"])
    }

    func testProjectionCatchUpRebuildsSQLiteIndexFromJSONLWhenDatabaseIsCorrupt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqliteURL = directory.appendingPathComponent("events.sqlite")
        let sqlite = SQLiteRuntimeEventRepository(url: sqliteURL)
        var logs: [String] = []
        let catchUp = RuntimeEventSQLiteProjectionCatchUp(
            primary: jsonl,
            secondary: sqlite,
            intervalSeconds: 0,
            log: { logs.append($0) }
        )

        try jsonl.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        try Data("not a sqlite database".utf8).write(to: sqliteURL)

        catchUp.catchUpIfDue()

        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["event-1"])
        XCTAssertTrue(logs.contains { $0.contains("runtime event sqlite catch-up failed; rebuilding index") })
    }

    func testProjectionCatchUpSkipsBrokenJSONLLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonlURL = directory.appendingPathComponent("events.jsonl")
        let jsonl = JSONLRuntimeEventRepository(url: jsonlURL)
        let sqlite = SQLiteRuntimeEventRepository(url: directory.appendingPathComponent("events.sqlite"))
        var logs: [String] = []
        let catchUp = RuntimeEventSQLiteProjectionCatchUp(
            primary: jsonl,
            secondary: sqlite,
            intervalSeconds: 0,
            log: { logs.append($0) }
        )

        try jsonl.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))
        let handle = try FileHandle(forWritingTo: jsonlURL)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        handle.write(Data("{broken json}\n".utf8))
        try jsonl.append(event(id: "event-2", timestamp: "2026-05-24T00:01:00Z", type: .containerObserved))

        catchUp.catchUpIfDue()

        XCTAssertEqual(sqlite.recent(limit: 10).map(\.id), ["event-1", "event-2"])
        XCTAssertTrue(logs.contains { $0.contains("runtime event jsonl read issue during sqlite catch-up") })
    }

    func testCompositeRepositoryFallsBackToJSONLWhenSQLiteQueryIsUnavailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jsonl = JSONLRuntimeEventRepository(url: directory.appendingPathComponent("events.jsonl"))
        let sqlite = SQLiteRuntimeEventRepository(url: URL(fileURLWithPath: "/dev/null/events.sqlite"))
        var logs: [String] = []
        let repository = CompositeRuntimeEventRepository(
            primary: jsonl,
            secondary: sqlite,
            log: { logs.append($0) }
        )

        try jsonl.append(event(id: "event-1", timestamp: "2026-05-24T00:00:00Z", type: .statusChanged))

        let page = repository.query(RuntimeEventQuery(limit: 10))

        XCTAssertEqual(page.events.map(\.id), ["event-1"])
        XCTAssertEqual(page.matchingCount, 1)
        XCTAssertNotNil(page.readError)
        XCTAssertTrue(logs.contains { $0.contains("served events from jsonl primary") })
    }

    func testStoresAndLoadsLatestVitalDBObservation() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }
        let older = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120
        )
        let newer = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", ip: "10.0.0.10", online: true),
            ]
        )

        try harness.store.append(older)
        try harness.store.append(newer)

        XCTAssertEqual(try harness.store.loadLatestVitalDBObservation(), newer)
    }

    func testLoadsVitalDBObservationsInChronologicalOrder() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }
        let older = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120
        )
        let newer = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120
        )

        try harness.store.append(newer)
        try harness.store.append(older)

        XCTAssertEqual(try harness.store.loadVitalDBObservations().map(\.observedAt), [
            "2026-05-25T00:00:00Z",
            "2026-05-25T00:01:00Z",
        ])
    }

    func testProjectsRecorderActivityBucketsFromVitalDBObservations() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:01:05Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_A",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 3,
                        byteCount: 900,
                        roomCount: 1,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-25T00:01:00Z",
                                bucketSeconds: 60,
                                messageCount: 3,
                                byteCount: 900,
                                roomCount: 1
                            ),
                        ]
                    )
                ),
            ]
        ))

        XCTAssertEqual(try harness.store.loadVitalDBRecorderActivityBuckets(), [
            VitalDBRecorderActivityBucketRecord(
                vrcode: "VR_A",
                bucketStartedAt: "2026-05-25T00:01:00Z",
                bucketSeconds: 60,
                messageCount: 3,
                byteCount: 900,
                roomCount: 1,
                firstObservedAt: "2026-05-25T00:01:05Z",
                lastObservedAt: "2026-05-25T00:01:05Z"
            ),
        ])
    }

    func testRecorderActivityBucketProjectionKeepsLargestObservedAggregate() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(recorderActivityObservation(
            observedAt: "2026-05-25T00:01:05Z",
            messageCount: 3,
            byteCount: 900
        ))
        try harness.store.append(recorderActivityObservation(
            observedAt: "2026-05-25T00:01:55Z",
            messageCount: 5,
            byteCount: 1500
        ))

        let bucket = try XCTUnwrap(try harness.store.loadVitalDBRecorderActivityBuckets().first)
        XCTAssertEqual(bucket.messageCount, 5)
        XCTAssertEqual(bucket.byteCount, 1500)
        XCTAssertEqual(bucket.firstObservedAt, "2026-05-25T00:01:05Z")
        XCTAssertEqual(bucket.lastObservedAt, "2026-05-25T00:01:55Z")
    }

    func testQueriesRecorderActivityBucketsByRecorderAndTimeRange() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(recorderActivityObservation(
            observedAt: "2026-05-25T00:00:10Z",
            vrcode: "VR_A",
            bucketStartedAt: "2026-05-25T00:00:00Z",
            messageCount: 1,
            byteCount: 100
        ))
        try harness.store.append(recorderActivityObservation(
            observedAt: "2026-05-25T00:01:10Z",
            vrcode: "VR_A",
            bucketStartedAt: "2026-05-25T00:01:00Z",
            messageCount: 2,
            byteCount: 200
        ))
        try harness.store.append(recorderActivityObservation(
            observedAt: "2026-05-25T00:01:20Z",
            vrcode: "VR_B",
            bucketStartedAt: "2026-05-25T00:01:00Z",
            messageCount: 3,
            byteCount: 300
        ))

        let records = try harness.store.loadVitalDBRecorderActivityBuckets(
            query: VitalDBRecorderActivityBucketQuery(
                vrcode: "VR_A",
                since: "2026-05-25T00:01:00Z",
                until: "2026-05-25T00:01:00Z"
            )
        )

        XCTAssertEqual(records.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(records.map(\.bucketStartedAt), ["2026-05-25T00:01:00Z"])
        XCTAssertEqual(records.map(\.messageCount), [2])
    }

    func testProjectsVitalDBBedAssignmentsAcrossObservations() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", ip: "10.0.0.10", online: true),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR A",
                    vrcode: "VR_A",
                    lastSeenAt: "2026-05-25T00:00:00Z",
                    patientConnected: true,
                    online: true
                ),
            ]
        ))
        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:01:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", ip: "10.0.0.10", online: true),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR A",
                    vrcode: "VR_A",
                    lastSeenAt: "2026-05-25T00:01:00Z",
                    patientConnected: true,
                    online: true
                ),
            ]
        ))

        let assignments = try harness.store.loadVitalDBBedAssignments()

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments[0].bedID, "bed-a")
        XCTAssertEqual(assignments[0].vrcode, "VR_A")
        XCTAssertEqual(assignments[0].startedAt, "2026-05-25T00:00:00Z")
        XCTAssertNil(assignments[0].endedAt)
        XCTAssertEqual(assignments[0].lastObservedAt, "2026-05-25T00:01:00Z")
        XCTAssertEqual(assignments[0].observationCount, 2)
    }

    func testRelationshipProjectionIsIdempotentForSameObservationTimestamp() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", ip: "10.0.0.10", online: true),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "OR A",
                    vrcode: "VR_A",
                    lastSeenAt: "2026-05-25T00:00:00Z",
                    patientConnected: true,
                    online: true
                ),
            ]
        )

        try harness.store.append(observation)
        try harness.store.append(observation)

        let assignments = try harness.store.loadVitalDBBedAssignments()

        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments[0].observationCount, 1)
    }


    func testProjectsVitalDBRelationshipHandoff() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", online: true),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "OR A", vrcode: "VR_A", online: true),
            ]
        ))
        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:05:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_B", online: true),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "OR A", vrcode: "VR_B", online: true),
            ]
        ))

        let assignments = try harness.store.loadVitalDBBedAssignments()
        let events = try harness.store.loadVitalDBRelationshipEvents()

        XCTAssertEqual(assignments.map(\.vrcode), ["VR_B", "VR_A"])
        XCTAssertNil(assignments[0].endedAt)
        XCTAssertEqual(assignments[1].endedAt, "2026-05-25T00:05:00Z")
        XCTAssertTrue(events.contains {
            $0.eventType == .handoff
                && $0.bedID == "bed-a"
                && $0.vrcode == "VR_B"
                && $0.previousVrcode == "VR_A"
        })
    }

    func testProjectsVitalDBRelationshipAnomalies() throws {
        let harness = try SQLiteStoreHarness()
        defer {
            harness.cleanup()
        }

        try harness.store.append(VitalDBObservationDocument(
            observedAt: "2026-05-25T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 120,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_DUP", online: true),
                VitalDBRecorderObservation(vrcode: "VR_FREE", online: true),
            ],
            beds: [
                VitalDBBedObservation(bedID: "bed-a", name: "OR A", vrcode: "VR_DUP", online: true),
                VitalDBBedObservation(bedID: "bed-b", name: "OR B", vrcode: "VR_DUP", online: true),
                VitalDBBedObservation(bedID: "bed-c", name: "OR C", vrcode: nil, online: true),
            ]
        ))

        let eventTypes = Set(try harness.store.loadVitalDBRelationshipEvents().map(\.eventType))

        XCTAssertTrue(eventTypes.contains(.duplicateAssignment))
        XCTAssertTrue(eventTypes.contains(.unlinkedBed))
        XCTAssertTrue(eventTypes.contains(.unlinkedRecorder))
    }

    private func event(id: String, timestamp: String, type: RuntimeEventType) -> RuntimeEventDocument {
        RuntimeEventDocument(
            id: id,
            eventType: type,
            timestamp: timestamp,
            product: "TiroshVitalServer",
            status: .healthy,
            previousStatus: nil,
            operation: .health,
            message: "message",
            runtimeVersion: "0.1.0",
            failureReasons: [],
            containerObservation: nil,
            progress: nil
        )
    }
}

private struct SQLiteStoreHarness {
    let directory: URL
    let store: SQLiteRuntimeObservabilityStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = SQLiteRuntimeObservabilityStore(url: directory.appendingPathComponent("runtime-observability.sqlite"))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func recorderActivityObservation(
    observedAt: String,
    vrcode: String = "VR_A",
    bucketStartedAt: String = "2026-05-25T00:01:00Z",
    messageCount: Int,
    byteCount: Int
) -> VitalDBObservationDocument {
    VitalDBObservationDocument(
        observedAt: observedAt,
        ready: true,
        recorderOnlineThresholdSeconds: 120,
        recorders: [
            VitalDBRecorderObservation(
                vrcode: vrcode,
                online: true,
                activity: VitalDBRecorderActivityObservation(
                    windowSeconds: 300,
                    messageCount: messageCount,
                    byteCount: byteCount,
                    roomCount: 1,
                    buckets: [
                        VitalDBRecorderActivityBucket(
                            bucketStartedAt: bucketStartedAt,
                            bucketSeconds: 60,
                            messageCount: messageCount,
                            byteCount: byteCount,
                            roomCount: 1
                        ),
                    ]
                )
            ),
        ]
    )
}
