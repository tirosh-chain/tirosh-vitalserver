import Application
import Contracts
import Errors
import Foundation
import SQLite3
import XCTest
@testable import OutboundAdapters

final class SQLiteRuntimeWorkflowOperationStateRepositoryTests: XCTestCase {
    func testMissingDatabaseIsFailedReadAndDoesNotCreateDatabase() throws {
        let databaseURL = try temporaryDirectory().appendingPathComponent("runtime-state.sqlite")
        let repository = SQLiteRuntimeWorkflowOperationStateRepository(databaseURL: databaseURL)

        guard case .failed(let reason) = repository.loadOperationState(operationID: "operation-1") else {
            return XCTFail("expected failed read")
        }
        XCTAssertTrue(reason.contains("SQLite read failed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testCreateAndUpdatePersistRevisionAndOutboxInOneTransaction() throws {
        let fixture = try makeRepository()

        let created = try fixture.repository.saveOperationState(mutation(
            operationID: "operation-1",
            phase: .running,
            step: .stopRuntimeServices,
            stepStatus: .started,
            occurredAt: "2026-07-14T06:00:00Z"
        ))
        let updated = try fixture.repository.saveOperationState(mutation(
            operationID: "operation-1",
            phase: .completed,
            step: .waitRuntimeHealth,
            stepStatus: .completed,
            occurredAt: "2026-07-14T06:05:00Z",
            completedAt: "2026-07-14T06:05:00Z",
            expectedRevision: created.revision
        ))

        XCTAssertEqual(created.revision, 1)
        XCTAssertEqual(updated.revision, 2)
        XCTAssertEqual(updated.startedAt, created.startedAt)
        XCTAssertEqual(updated.completedAt, "2026-07-14T06:05:00Z")
        XCTAssertEqual(fixture.repository.loadOperationState(operationID: "operation-1"), .loaded(updated))
        XCTAssertEqual(fixture.repository.loadLatestOperationState(operation: .applyBundle), .loaded(updated))
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 2)
        XCTAssertEqual(try stringRows(
            fixture.databaseURL,
            "SELECT event_type FROM diagnostic_outbox ORDER BY sequence"
        ), [
            "workflow-operation-state-created",
            "workflow-operation-state-updated",
        ])
        XCTAssertEqual(try intRows(
            fixture.databaseURL,
            "SELECT aggregate_revision FROM diagnostic_outbox ORDER BY sequence"
        ), [1, 2])
    }

    func testStaleRevisionRejectsMutationWithoutChangingStateOrOutbox() throws {
        let fixture = try makeRepository()
        let created = try fixture.repository.saveOperationState(mutation(
            operationID: "operation-1",
            occurredAt: "2026-07-14T06:00:00Z"
        ))

        XCTAssertThrowsError(try fixture.repository.saveOperationState(mutation(
            operationID: "operation-1",
            phase: .failed,
            occurredAt: "2026-07-14T06:05:00Z",
            expectedRevision: created.revision + 1
        ))) { error in
            XCTAssertEqual(
                error as? SQLiteRuntimeWorkflowOperationStateRepositoryError,
                .staleRevision(operationID: "operation-1", expected: 2, actual: 1)
            )
        }
        XCTAssertEqual(fixture.repository.loadOperationState(operationID: "operation-1"), .loaded(created))
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 1)
    }

    func testCreateRejectsExistingOperationAndUpdateRejectsMissingOperation() throws {
        let fixture = try makeRepository()
        let created = try fixture.repository.saveOperationState(mutation(
            operationID: "operation-1",
            occurredAt: "2026-07-14T06:00:00Z"
        ))

        XCTAssertThrowsError(try fixture.repository.saveOperationState(mutation(
            operationID: "operation-1",
            occurredAt: "2026-07-14T06:01:00Z"
        ))) { error in
            XCTAssertEqual(
                error as? SQLiteRuntimeWorkflowOperationStateRepositoryError,
                .alreadyExists(operationID: "operation-1", revision: 1)
            )
        }
        XCTAssertThrowsError(try fixture.repository.saveOperationState(mutation(
            operationID: "operation-missing",
            occurredAt: "2026-07-14T06:01:00Z",
            expectedRevision: 1
        ))) { error in
            XCTAssertEqual(
                error as? SQLiteRuntimeWorkflowOperationStateRepositoryError,
                .missing(operationID: "operation-missing")
            )
        }
        XCTAssertEqual(fixture.repository.loadOperationState(operationID: "operation-1"), .loaded(created))
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 1)
    }

    func testOperationTypeCannotChangeWithinOneOperationID() throws {
        let fixture = try makeRepository()
        let created = try fixture.repository.saveOperationState(mutation(
            operationID: "operation-1",
            occurredAt: "2026-07-14T06:00:00Z"
        ))

        XCTAssertThrowsError(try fixture.repository.saveOperationState(
            RuntimeWorkflowOperationStateMutation(
                operationID: "operation-1",
                operation: .rollback,
                phase: .running,
                currentStep: .rollbackStopRuntimeServices,
                stepStatus: .started,
                message: "rollback",
                occurredAt: "2026-07-14T06:01:00Z",
                expectedRevision: created.revision
            )
        )) { error in
            XCTAssertEqual(
                error as? SQLiteRuntimeWorkflowOperationStateRepositoryError,
                .operationMismatch(operationID: "operation-1", expected: "apply-bundle", actual: "rollback")
            )
        }
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 1)
    }

    func testOutboxFailureRollsBackStateUpdate() throws {
        let databaseURL = try temporaryDirectory().appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        let repository = SQLiteRuntimeWorkflowOperationStateRepository(
            databaseURL: databaseURL,
            eventID: { "duplicate-event-id" }
        )
        let created = try repository.saveOperationState(mutation(
            operationID: "operation-1",
            occurredAt: "2026-07-14T06:00:00Z"
        ))

        XCTAssertThrowsError(try repository.saveOperationState(mutation(
            operationID: "operation-1",
            phase: .completed,
            occurredAt: "2026-07-14T06:05:00Z",
            completedAt: "2026-07-14T06:05:00Z",
            expectedRevision: created.revision
        ))) { error in
            guard case .writeFailed(_, let reason) = error as? SQLiteRuntimeWorkflowOperationStateRepositoryError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("UNIQUE constraint failed"))
        }
        XCTAssertEqual(repository.loadOperationState(operationID: "operation-1"), .loaded(created))
        XCTAssertEqual(try scalarInt(databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 1)
    }

    func testInvalidPersistedEnumIsFailedReadInsteadOfUnknownState() throws {
        let fixture = try makeRepository()
        _ = try fixture.repository.saveOperationState(mutation(
            operationID: "operation-1",
            occurredAt: "2026-07-14T06:00:00Z"
        ))
        try executeSQL(
            fixture.databaseURL,
            "UPDATE workflow_operation_states SET phase = 'future-phase' WHERE operation_id = 'operation-1'"
        )

        guard case .failed(let reason) = fixture.repository.loadOperationState(operationID: "operation-1") else {
            return XCTFail("expected failed read")
        }
        XCTAssertTrue(reason.contains("field=phase"))
        XCTAssertTrue(reason.contains("future-phase"))
    }

    func testLoadsLatestWorkflowStateAcrossOperationTypes() throws {
        let fixture = try makeRepository()
        let older = try fixture.repository.saveOperationState(mutation(
            operationID: "operation-older",
            occurredAt: "2026-07-14T06:00:00Z"
        ))
        let newer = try fixture.repository.saveOperationState(RuntimeWorkflowOperationStateMutation(
            operationID: "operation-newer",
            operation: .rollback,
            phase: .running,
            currentStep: .rollbackStopRuntimeServices,
            stepStatus: .started,
            message: "rollback progress",
            occurredAt: "2026-07-14T06:05:00Z"
        ))

        XCTAssertEqual(fixture.repository.loadLatestOperationState(), .loaded(newer))
        XCTAssertEqual(fixture.repository.loadLatestOperationState(operation: .applyBundle), .loaded(older))
    }

    private func makeRepository() throws -> (
        repository: SQLiteRuntimeWorkflowOperationStateRepository,
        databaseURL: URL
    ) {
        let databaseURL = try temporaryDirectory().appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        return (
            SQLiteRuntimeWorkflowOperationStateRepository(databaseURL: databaseURL),
            databaseURL
        )
    }

    private func mutation(
        operationID: String,
        phase: RuntimeProgressPhase = .running,
        step: RuntimeWorkflowStep? = .stopRuntimeServices,
        stepStatus: RuntimeProgressStepStatus? = .started,
        occurredAt: String,
        completedAt: String? = nil,
        expectedRevision: Int? = nil
    ) -> RuntimeWorkflowOperationStateMutation {
        RuntimeWorkflowOperationStateMutation(
            operationID: operationID,
            operation: .applyBundle,
            phase: phase,
            currentStep: step,
            stepStatus: stepStatus,
            message: "operation progress",
            reasonCodes: ["test"],
            occurredAt: occurredAt,
            completedAt: completedAt,
            expectedRevision: expectedRevision
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteRuntimeWorkflowOperationStateRepositoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func scalarInt(_ url: URL, _ sql: String) throws -> Int {
        Int(try scalarString(url, sql) ?? "") ?? -1
    }

    private func scalarString(_ url: URL, _ sql: String) throws -> String? {
        try withDatabase(url) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TestFailure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw TestFailure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            guard let value = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: value)
        }
    }

    private func stringRows(_ url: URL, _ sql: String) throws -> [String] {
        try withDatabase(url) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TestFailure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            var values: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let value = sqlite3_column_text(statement, 0) else {
                    throw TestFailure.sqlite("unexpected NULL")
                }
                values.append(String(cString: value))
            }
            return values
        }
    }

    private func intRows(_ url: URL, _ sql: String) throws -> [Int] {
        try stringRows(url, sql).compactMap(Int.init)
    }

    private func executeSQL(_ url: URL, _ sql: String) throws {
        try withDatabase(url, readOnly: false) { db in
            var errorMessage: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
                let message = errorMessage.map { String(cString: $0) }
                    ?? String(cString: sqlite3_errmsg(db))
                sqlite3_free(errorMessage)
                throw TestFailure.sqlite(message)
            }
        }
    }

    private func withDatabase<T>(
        _ url: URL,
        readOnly: Bool = true,
        operation: (OpaquePointer) throws -> T
    ) throws -> T {
        var db: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw TestFailure.sqlite("open failed")
        }
        defer { sqlite3_close(db) }
        return try operation(db)
    }
}

private enum TestFailure: Error {
    case sqlite(String)
}
