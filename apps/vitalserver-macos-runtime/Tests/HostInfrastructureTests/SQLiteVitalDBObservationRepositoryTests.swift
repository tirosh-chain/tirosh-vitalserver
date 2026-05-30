import Contracts
import HostInfrastructure
import XCTest

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
        XCTAssertEqual(relationshipEvents, [])
    }
}

private struct Harness {
    let directory: URL
    let repository: SQLiteVitalDBObservationRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = SQLiteVitalDBObservationRepository(
            url: directory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
