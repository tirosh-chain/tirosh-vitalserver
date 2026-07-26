import Application
import Domain
import Foundation
import OutboundAdapters
import Workflow
import XCTest

final class RuntimeHostDiagnosticsProjectionWorkflowTests: XCTestCase {
    func testProjectsOutboxAndCurrentSnapshotWithIndependentCheckpoints() throws {
        let harness = try Harness()

        let first = try harness.workflow().run()
        let second = try harness.workflow().run()

        XCTAssertEqual(first, RuntimeHostDiagnosticsProjectionResult(
            projectedEventCount: 1,
            snapshotSourceSequence: 1
        ))
        XCTAssertEqual(second, RuntimeHostDiagnosticsProjectionResult(
            projectedEventCount: 0,
            snapshotSourceSequence: 1
        ))
        XCTAssertEqual(try harness.repository.loadPendingDiagnosticEvents(limit: 10), [])
        XCTAssertEqual(
            try harness.repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.eventLog
            )?.lastSequence,
            1
        )
        XCTAssertEqual(
            try harness.repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot
            )?.lastSequence,
            1
        )
        XCTAssertEqual(
            try String(contentsOf: harness.eventsURL, encoding: .utf8).split(separator: "\n").count,
            1
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                RuntimeHostStateDiagnosticSnapshot.self,
                from: Data(contentsOf: harness.snapshotURL)
            ).sourceSequence,
            1
        )
    }

    func testCorruptEventLogDoesNotBlockCurrentSnapshotAndFailureRemainsRetryable() throws {
        let harness = try Harness()
        try Data("corrupt".utf8).write(to: harness.eventsURL, options: .atomic)

        XCTAssertThrowsError(try harness.workflow().run()) { error in
            guard case RuntimeHostDiagnosticsProjectionWorkflowError.projectionFailed(let failures) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(failures.map(\.projectionName), [RuntimeHostDiagnosticProjectionNames.eventLog])
            XCTAssertEqual(failures.map(\.sourceSequence), [1])
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.snapshotURL.path))
        XCTAssertEqual(
            try harness.repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot
            )?.lastSequence,
            1
        )
        XCTAssertEqual(
            try harness.repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.eventLog
            )?.failureAttempts,
            1
        )
        XCTAssertEqual(try harness.repository.loadPendingDiagnosticEvents(limit: 10).map(\.sequence), [1])

        try FileManager.default.removeItem(at: harness.eventsURL)
        XCTAssertEqual(try harness.workflow().run().projectedEventCount, 1)
        XCTAssertEqual(
            try harness.repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.eventLog
            )?.failureAttempts,
            0
        )
    }

    func testSnapshotFailureDoesNotRollBackProjectedJSONLEventAndRetryRepairsSnapshot() throws {
        let harness = try Harness()
        try FileManager.default.createDirectory(at: harness.snapshotURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try harness.workflow().run()) { error in
            guard case RuntimeHostDiagnosticsProjectionWorkflowError.projectionFailed(let failures) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(failures.map(\.projectionName), [RuntimeHostDiagnosticProjectionNames.currentSnapshot])
        }

        XCTAssertEqual(try harness.repository.loadPendingDiagnosticEvents(limit: 10), [])
        XCTAssertEqual(
            try harness.repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.eventLog
            )?.lastSequence,
            1
        )
        XCTAssertEqual(
            try harness.repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot
            )?.failureAttempts,
            1
        )

        try FileManager.default.removeItem(at: harness.snapshotURL)
        let retried = try harness.workflow().run()
        XCTAssertEqual(retried.projectedEventCount, 0)
        XCTAssertEqual(retried.snapshotSourceSequence, 1)
        XCTAssertEqual(
            try harness.repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot
            )?.failureAttempts,
            0
        )
    }

    private final class Harness {
        let directory: URL
        let databaseURL: URL
        let eventsURL: URL
        let snapshotURL: URL
        let repository: SQLiteRuntimeHostDiagnosticOutboxRepository

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("host-diagnostic-workflow-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
            eventsURL = directory.appendingPathComponent("host-runtime-state-events.jsonl")
            snapshotURL = directory.appendingPathComponent("host-runtime-state.json")
            _ = try SQLiteHostRuntimeStateDatabase(
                url: databaseURL,
                databaseID: { "workflow-db" },
                timestamp: { "2026-07-14T10:00:00Z" }
            ).initialize()
            let settings = SQLiteRuntimeHostSettingsRepository(
                databaseURL: databaseURL,
                transitionDecider: RuntimeHostSettingsActivationUseCase(),
                eventID: { "settings-event-1" }
            )
            let data = Data("{\"value\":1}".utf8)
            _ = try settings.importMaterializedHostSettings(
                RuntimeHostSettingsPayload(
                    vmConfigJSON: data,
                    guestRuntimeConfigJSON: data,
                    guestRuntimeSettingsJSON: data
                ),
                importedAt: "2026-07-14T10:00:00Z"
            )
            repository = SQLiteRuntimeHostDiagnosticOutboxRepository(databaseURL: databaseURL)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func workflow() -> RuntimeHostDiagnosticsProjectionWorkflow {
            RuntimeHostDiagnosticsProjectionWorkflow(
                repository: repository,
                eventSink: JSONLRuntimeHostDiagnosticEventSink(url: eventsURL),
                snapshotSink: JSONRuntimeHostStateDiagnosticSnapshotSink(url: snapshotURL),
                timestamp: { "2026-07-14T10:01:00Z" },
                describeError: { String(describing: $0) }
            )
        }
    }
}
