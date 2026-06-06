import Contracts
import OutboundAdapters
import SQLite3
import XCTest
import Errors

final class SQLiteVitalDBObservationRepositoryTests: XCTestCase {
    func testRepositoryAppendsObservationAndLoadsVitalDBProjection() throws {
        let harness = try Harness()
        defer {
            harness.cleanup()
        }
        let observation = VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(
                    vrcode: "VR_A",
                    online: true,
                    activity: VitalDBRecorderActivityObservation(
                        windowSeconds: 300,
                        messageCount: 2,
                        byteCount: 512,
                        roomCount: 1,
                        messagesPerSecond: 0.01,
                        bytesPerSecond: 1.7,
                        buckets: [
                            VitalDBRecorderActivityBucket(
                                bucketStartedAt: "2026-05-30T00:00:00Z",
                                bucketSeconds: 60,
                                messageCount: 2,
                                byteCount: 512,
                                roomCount: 1
                            ),
                        ]
                    )
                ),
            ]
        )

        try harness.repository.append(observation)

        XCTAssertEqual(try harness.repository.loadLatestObservation(), observation)
        XCTAssertEqual(try harness.repository.loadObservations().map(\.observedAt), ["2026-05-30T00:00:00Z"])
        XCTAssertEqual(try harness.repository.loadRecorderActivityBuckets().map(\.vrcode), ["VR_A"])
    }

    func testRepositoryLoadsRelationshipProjection() throws {
        let harness = try Harness()
        defer {
            harness.cleanup()
        }
        try harness.repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            recorders: [
                VitalDBRecorderObservation(vrcode: "VR_A", online: true),
            ],
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    name: "A",
                    vrcode: "VR_A",
                    online: true
                ),
            ]
        ))

        let assignments = try harness.repository.loadBedAssignments()
        let relationshipEvents = try harness.repository.loadRelationshipEvents()

        XCTAssertEqual(assignments.map(\.bedID), ["bed-a"])
        XCTAssertEqual(assignments.map(\.vrcode), ["VR_A"])
        XCTAssertEqual(assignments.map(\.status), [.online])
        XCTAssertEqual(relationshipEvents, [])
    }

    func testRepositoryRejectsInvalidBedAssignmentStatus() throws {
        let harness = try Harness()
        defer {
            harness.cleanup()
        }
        try harness.repository.append(VitalDBObservationDocument(
            observedAt: "2026-05-30T00:00:00Z",
            ready: true,
            recorderOnlineThresholdSeconds: 60,
            beds: [
                VitalDBBedObservation(
                    bedID: "bed-a",
                    vrcode: "VR_A",
                    online: true
                ),
            ]
        ))
        try harness.executeSQL("UPDATE vitaldb_bed_assignments SET status = 'future-status'")

        XCTAssertThrowsError(try harness.repository.loadBedAssignments()) { error in
            XCTAssertEqual(
                error as? SQLiteRuntimeObservabilityStoreError,
                .invalidColumnValue(
                    table: "vitaldb_bed_assignments",
                    column: "status",
                    value: "future-status"
                )
            )
        }
    }
}

private struct Harness {
    let directory: URL
    let database: URL
    let repository: SQLiteVitalDBObservationRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        database = directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        repository = SQLiteVitalDBObservationRepository(url: database)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    func executeSQL(_ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(database.path, &db) == SQLITE_OK, let openedDB = db else {
            throw SQLiteRuntimeObservabilityStoreError.openFailed(
                String(cString: sqlite3_errmsg(db))
            )
        }
        defer {
            sqlite3_close(openedDB)
        }
        guard sqlite3_exec(openedDB, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteRuntimeObservabilityStoreError.stepFailed(
                String(cString: sqlite3_errmsg(openedDB))
            )
        }
    }
}
