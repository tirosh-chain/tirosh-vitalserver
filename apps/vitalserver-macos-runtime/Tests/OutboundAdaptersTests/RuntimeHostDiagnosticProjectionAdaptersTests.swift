import Application
import Contracts
import Domain
import Foundation
import XCTest
@testable import OutboundAdapters

final class RuntimeHostDiagnosticProjectionAdaptersTests: XCTestCase {
    func testJSONLAppendIsContiguousIdempotentAndPrivate() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("host-runtime-state-events.jsonl")
        let sink = JSONLRuntimeHostDiagnosticEventSink(url: url)
        let first = event(sequence: 1, eventID: "event-1")
        let second = event(sequence: 2, eventID: "event-2")

        try sink.appendDiagnosticEvent(first)
        try sink.appendDiagnosticEvent(second)
        try sink.appendDiagnosticEvent(first)

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeHostDiagnosticOutboxEvent.self, from: Data(lines[0].utf8)),
            first
        )
        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeHostDiagnosticOutboxEvent.self, from: Data(lines[1].utf8)),
            second
        )
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testJSONLAppendRejectsConflictGapAndCorruptionWithoutReplacingHistory() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("host-runtime-state-events.jsonl")
        let sink = JSONLRuntimeHostDiagnosticEventSink(url: url)
        try sink.appendDiagnosticEvent(event(sequence: 1, eventID: "event-1"))
        let original = try Data(contentsOf: url)

        XCTAssertThrowsError(try sink.appendDiagnosticEvent(event(sequence: 1, eventID: "other"))) { error in
            guard case JSONLRuntimeHostDiagnosticEventSinkError.duplicateConflict = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(try sink.appendDiagnosticEvent(event(sequence: 3, eventID: "event-3"))) { error in
            XCTAssertEqual(
                error as? JSONLRuntimeHostDiagnosticEventSinkError,
                .sequenceGap(path: url.path, expected: 2, actual: 3)
            )
        }
        XCTAssertEqual(try Data(contentsOf: url), original)

        try Data("not-json".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try sink.appendDiagnosticEvent(event(sequence: 2, eventID: "event-2"))) { error in
            XCTAssertEqual(
                error as? JSONLRuntimeHostDiagnosticEventSinkError,
                .missingTrailingNewline(path: url.path)
            )
        }
        XCTAssertEqual(try Data(contentsOf: url), Data("not-json".utf8))
    }

    func testSnapshotSinkWritesRoundTrippablePrivateCurrentJSON() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("host-runtime-state.json")
        let snapshot = RuntimeHostStateDiagnosticSnapshot(
            databaseID: "database-1",
            databaseSchemaVersion: 6,
            sourceSequence: 3,
            generatedAt: "2026-07-14T09:00:00Z",
            operationLeaseState: nil,
            operationLease: nil,
            operationLeaseRevision: nil,
            vmLifecycle: nil,
            vmLifecycleRevision: nil,
            runtimeEndpoint: nil,
            hostSettings: nil,
            workflowOperations: []
        )

        try JSONRuntimeHostStateDiagnosticSnapshotSink(url: url)
            .writeHostStateDiagnosticSnapshot(snapshot)

        XCTAssertEqual(
            try JSONDecoder().decode(RuntimeHostStateDiagnosticSnapshot.self, from: Data(contentsOf: url)),
            snapshot
        )
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testSQLiteOutboxUsesContiguousEventCheckpointAndSecretFreeSnapshot() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "diagnostic-db" },
            timestamp: { "2026-07-14T09:00:00Z" }
        ).initialize()
        let settings = SQLiteRuntimeHostSettingsRepository(
            databaseURL: databaseURL,
            transitionDecider: RuntimeHostSettingsActivationUseCase(),
            eventID: { UUID().uuidString }
        )
        _ = try settings.importMaterializedHostSettings(
            payload("first-secret"),
            importedAt: "2026-07-14T09:00:00Z"
        )
        _ = try settings.saveDesiredHostSettings(
            payload("second-secret"),
            expectedRevision: 1,
            desiredAt: "2026-07-14T09:01:00Z"
        )
        let repository = SQLiteRuntimeHostDiagnosticOutboxRepository(databaseURL: databaseURL)

        let events = try repository.loadPendingDiagnosticEvents(limit: 10)
        XCTAssertEqual(events.map(\.sequence), [1, 2])
        XCTAssertThrowsError(try repository.markDiagnosticEventProjected(
            sequence: 2,
            projectionName: RuntimeHostDiagnosticProjectionNames.eventLog,
            projectedAt: "2026-07-14T09:02:00Z"
        )) { error in
            XCTAssertEqual(
                error as? SQLiteRuntimeHostDiagnosticOutboxRepositoryError,
                .checkpointGap(
                    projection: RuntimeHostDiagnosticProjectionNames.eventLog,
                    current: 0,
                    proposed: 2
                )
            )
        }

        try repository.markDiagnosticEventProjected(
            sequence: 1,
            projectionName: RuntimeHostDiagnosticProjectionNames.eventLog,
            projectedAt: "2026-07-14T09:02:00Z"
        )
        try repository.recordDiagnosticProjectionFailure(
            projectionName: RuntimeHostDiagnosticProjectionNames.eventLog,
            sourceSequence: 2,
            reason: "disk denied",
            failedAt: "2026-07-14T09:03:00Z"
        )
        XCTAssertEqual(
            try repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.eventLog
            ),
            RuntimeHostDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.eventLog,
                lastSequence: 1,
                updatedAt: "2026-07-14T09:03:00Z",
                failureAttempts: 1,
                lastError: "disk denied"
            )
        )
        XCTAssertEqual(try repository.loadPendingDiagnosticEvents(limit: 10).map(\.sequence), [2])

        let snapshot = try repository.loadHostStateDiagnosticSnapshot(
            generatedAt: "2026-07-14T09:04:00Z"
        )
        XCTAssertEqual(snapshot.databaseID, "diagnostic-db")
        XCTAssertEqual(snapshot.sourceSequence, 2)
        XCTAssertEqual(snapshot.hostSettings?.revision, 2)
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("first-secret"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("second-secret"))
    }

    private func event(sequence: Int, eventID: String) -> RuntimeHostDiagnosticOutboxEvent {
        RuntimeHostDiagnosticOutboxEvent(
            sequence: sequence,
            eventID: eventID,
            aggregateType: "host-settings",
            aggregateID: "singleton",
            aggregateRevision: sequence,
            eventType: "changed",
            occurredAt: "2026-07-14T09:00:0\(sequence)Z",
            payloadJSON: "{\"revision\":\(sequence)}"
        )
    }

    private func payload(_ secret: String) -> RuntimeHostSettingsPayload {
        let data = Data("{\"adminPassword\":\"\(secret)\"}".utf8)
        return RuntimeHostSettingsPayload(
            vmConfigJSON: data,
            guestRuntimeConfigJSON: data,
            guestRuntimeSettingsJSON: data
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("host-diagnostic-projection-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
