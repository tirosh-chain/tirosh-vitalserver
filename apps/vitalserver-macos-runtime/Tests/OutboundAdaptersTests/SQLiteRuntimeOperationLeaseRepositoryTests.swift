import Application
import Contracts
import Errors
import Foundation
import SQLite3
import XCTest
@testable import OutboundAdapters

final class SQLiteRuntimeOperationLeaseRepositoryTests: XCTestCase {
    func testMissingDatabaseIsReadFailureAndReadDoesNotCreateDatabase() throws {
        let databaseURL = try temporaryDirectory().appendingPathComponent("runtime-state.sqlite")
        let repository = SQLiteRuntimeOperationLeaseRepository(databaseURL: databaseURL)

        guard case .failed(let reason) = repository.loadOperationLease() else {
            return XCTFail("expected explicit database failure")
        }
        XCTAssertTrue(reason.contains("SQLite read failed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testAcquireHeartbeatAndReleasePersistLeaseAndOutboxRevisionsAtomically() throws {
        let fixture = try makeRepository()
        let document = lease(operationID: "lease-1")

        try fixture.repository.acquire(document)
        XCTAssertEqual(fixture.repository.loadOperationLease(), .loaded(document))

        try fixture.repository.heartbeat(
            operationId: document.operationId,
            heartbeatAt: "2026-07-14T05:05:00Z",
            expiresAt: "2026-07-14T06:05:00Z"
        )
        guard case .loaded(let heartbeat) = fixture.repository.loadOperationLease() else {
            return XCTFail("expected active lease")
        }
        XCTAssertEqual(heartbeat.startedAt, document.startedAt)
        XCTAssertEqual(heartbeat.heartbeatAt, "2026-07-14T05:05:00Z")
        XCTAssertEqual(heartbeat.expiresAt, "2026-07-14T06:05:00Z")

        try fixture.repository.release(operationId: document.operationId)
        XCTAssertEqual(fixture.repository.loadOperationLease(), .missing)
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT revision FROM runtime_operation_lease"), 3)
        XCTAssertEqual(try scalarString(fixture.databaseURL, "SELECT state FROM runtime_operation_lease"), "released")
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 3)
        XCTAssertEqual(try stringRows(
            fixture.databaseURL,
            "SELECT event_type FROM diagnostic_outbox ORDER BY sequence"
        ), [
            "operation-lease-acquired",
            "operation-lease-heartbeat",
            "operation-lease-released",
        ])
        XCTAssertEqual(try intRows(
            fixture.databaseURL,
            "SELECT aggregate_revision FROM diagnostic_outbox ORDER BY sequence"
        ), [1, 2, 3])
    }

    func testAcquireRejectsExistingActiveLeaseWithoutAddingOutboxEvent() throws {
        let fixture = try makeRepository()
        let existing = lease(operationID: "lease-1")
        try fixture.repository.acquire(existing)

        XCTAssertThrowsError(try fixture.repository.acquire(lease(operationID: "lease-2"))) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseOwnerError,
                .existingOperation(operationId: "lease-1", operation: "apply-bundle")
            )
        }
        XCTAssertEqual(fixture.repository.loadOperationLease(), .loaded(existing))
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 1)
    }

    func testOperationIDMismatchRollsBackLeaseAndOutbox() throws {
        let fixture = try makeRepository()
        let existing = lease(operationID: "lease-1")
        try fixture.repository.acquire(existing)

        XCTAssertThrowsError(try fixture.repository.release(operationId: "lease-2")) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseOwnerError,
                .operationIdMismatch(expected: "lease-2", actual: "lease-1")
            )
        }
        XCTAssertEqual(fixture.repository.loadOperationLease(), .loaded(existing))
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT revision FROM runtime_operation_lease"), 1)
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 1)
    }

    func testOutboxFailureRollsBackReleaseState() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        let repository = SQLiteRuntimeOperationLeaseRepository(
            databaseURL: databaseURL,
            eventID: { "duplicate-event-id" },
            timestamp: { "2026-07-14T05:00:00Z" }
        )
        let document = lease(operationID: "lease-1")
        try repository.acquire(document)

        XCTAssertThrowsError(try repository.release(operationId: document.operationId)) { error in
            guard case .writeFailed(let reason) = error as? RuntimeOperationLeaseOwnerError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("UNIQUE constraint failed"))
        }
        XCTAssertEqual(repository.loadOperationLease(), .loaded(document))
        XCTAssertEqual(try scalarInt(databaseURL, "SELECT revision FROM runtime_operation_lease"), 1)
        XCTAssertEqual(try scalarInt(databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 1)
    }

    func testReleasedLeaseCanBeReplacedWithoutResettingRevision() throws {
        let fixture = try makeRepository()
        try fixture.repository.acquire(lease(operationID: "lease-1"))
        try fixture.repository.release(operationId: "lease-1")
        let replacement = lease(operationID: "lease-2")

        try fixture.repository.acquire(replacement)

        XCTAssertEqual(fixture.repository.loadOperationLease(), .loaded(replacement))
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT revision FROM runtime_operation_lease"), 3)
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 3)
    }

    func testReleaseIsIdempotentAfterExplicitReleasedState() throws {
        let fixture = try makeRepository()
        try fixture.repository.acquire(lease(operationID: "lease-1"))
        try fixture.repository.release(operationId: "lease-1")

        try fixture.repository.release(operationId: "lease-1")

        XCTAssertEqual(fixture.repository.loadOperationLease(), .missing)
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT revision FROM runtime_operation_lease"), 2)
        XCTAssertEqual(try scalarInt(fixture.databaseURL, "SELECT COUNT(*) FROM diagnostic_outbox"), 2)
    }

    private func makeRepository() throws -> (
        repository: SQLiteRuntimeOperationLeaseRepository,
        databaseURL: URL
    ) {
        let databaseURL = try temporaryDirectory().appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "lease-test-db" },
            timestamp: { "2026-07-14T04:00:00Z" }
        ).initialize()
        return (
            SQLiteRuntimeOperationLeaseRepository(
                databaseURL: databaseURL,
                timestamp: { "2026-07-14T05:00:00Z" }
            ),
            databaseURL
        )
    }

    private func lease(operationID: String) -> RuntimeOperationLeaseDocument {
        RuntimeOperationLeaseDocument(
            operationId: operationID,
            operation: .applyBundle,
            ownerPID: 123,
            startedAt: "2026-07-14T05:00:00Z",
            heartbeatAt: "2026-07-14T05:00:00Z",
            expiresAt: nil,
            message: "test"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteRuntimeOperationLeaseRepositoryTests-\(UUID().uuidString)")
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

    private func withDatabase<T>(_ url: URL, operation: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw TestFailure.sqlite("open failed")
        }
        defer { sqlite3_close(db) }
        return try operation(db)
    }
}

private enum TestFailure: Error {
    case sqlite(String)
}
