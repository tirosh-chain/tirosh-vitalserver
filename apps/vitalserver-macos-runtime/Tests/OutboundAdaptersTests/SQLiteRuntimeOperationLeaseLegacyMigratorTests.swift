import Application
import Contracts
import Errors
import Foundation
import SQLite3
import XCTest
@testable import OutboundAdapters

final class SQLiteRuntimeOperationLeaseLegacyMigratorTests: XCTestCase {
    func testMissingSourceIsRecordedExplicitlyAndDoesNotCreateLease() throws {
        let fixture = try makeFixture()

        XCTAssertEqual(try fixture.migrator.migrate(), .sourceMissing)
        XCTAssertEqual(
            SQLiteRuntimeOperationLeaseRepository(databaseURL: fixture.databaseURL)
                .loadOperationLease(),
            .missing
        )
        XCTAssertEqual(try scalarString(
            fixture.databaseURL,
            "SELECT source_state FROM legacy_state_imports"
        ), "missing")
        XCTAssertEqual(
            try fixture.migrator.migrate(),
            .alreadyCompleted(sourceState: "missing", archivePath: nil)
        )
    }

    func testValidLegacyDocumentImportsLeaseAndOutboxThenArchivesSource() throws {
        let fixture = try makeFixture()
        let document = lease(operationID: "legacy-lease")
        try JSONEncoder().encode(document).write(to: fixture.sourceURL)

        XCTAssertEqual(
            try fixture.migrator.migrate(),
            .imported(operationId: document.operationId, archivePath: fixture.archiveURL.path)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.archiveURL.path))
        XCTAssertEqual(
            SQLiteRuntimeOperationLeaseRepository(databaseURL: fixture.databaseURL)
                .loadOperationLease(),
            .loaded(document)
        )
        XCTAssertEqual(try scalarString(
            fixture.databaseURL,
            "SELECT source_state FROM legacy_state_imports"
        ), "imported")
        XCTAssertEqual(try scalarString(
            fixture.databaseURL,
            "SELECT event_type FROM diagnostic_outbox"
        ), "operation-lease-legacy-imported")
    }

    func testInvalidLegacyDocumentStopsWithoutImportRecordOrLease() throws {
        let fixture = try makeFixture()
        try Data("not-json".utf8).write(to: fixture.sourceURL)

        XCTAssertThrowsError(try fixture.migrator.migrate()) { error in
            guard case .sourceDecodeFailed(let path, _) = error as? RuntimeOperationLeaseLegacyMigrationError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, fixture.sourceURL.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceURL.path))
        XCTAssertEqual(try scalarInt(
            fixture.databaseURL,
            "SELECT COUNT(*) FROM legacy_state_imports"
        ), 0)
        XCTAssertEqual(
            SQLiteRuntimeOperationLeaseRepository(databaseURL: fixture.databaseURL)
                .loadOperationLease(),
            .missing
        )
    }

    func testExistingArchiveStopsBeforeImportingSource() throws {
        let fixture = try makeFixture()
        try JSONEncoder().encode(lease(operationID: "legacy-lease")).write(to: fixture.sourceURL)
        try Data("older archive".utf8).write(to: fixture.archiveURL)

        XCTAssertThrowsError(try fixture.migrator.migrate()) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseLegacyMigrationError,
                .archiveConflict(path: fixture.archiveURL.path)
            )
        }
        XCTAssertEqual(try scalarInt(
            fixture.databaseURL,
            "SELECT COUNT(*) FROM legacy_state_imports"
        ), 0)
    }

    func testRetryCompletesArchiveAfterDatabaseCommit() throws {
        let fixture = try makeFixture()
        let document = lease(operationID: "legacy-lease")
        try JSONEncoder().encode(document).write(to: fixture.sourceURL)
        _ = try SQLiteHostRuntimeStateDatabase(url: fixture.databaseURL).initialize()
        try SQLiteRuntimeOperationLeaseRepository(databaseURL: fixture.databaseURL)
            .importLegacyDocument(
                document,
                migrationID: SQLiteRuntimeOperationLeaseLegacyMigrator.migrationID,
                sourcePath: fixture.sourceURL.path,
                completedAt: "2026-07-14T05:00:00Z"
            )

        XCTAssertEqual(
            try fixture.migrator.migrate(),
            .alreadyCompleted(sourceState: "imported", archivePath: fixture.archiveURL.path)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.archiveURL.path))
    }

    func testSourceAppearingAfterMissingMigrationIsExplicitConflict() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(try fixture.migrator.migrate(), .sourceMissing)
        try JSONEncoder().encode(lease(operationID: "late-lease")).write(to: fixture.sourceURL)

        XCTAssertThrowsError(try fixture.migrator.migrate()) { error in
            XCTAssertEqual(
                error as? RuntimeOperationLeaseLegacyMigrationError,
                .sourceReappeared(path: fixture.sourceURL.path, completedState: "missing")
            )
        }
    }

    private func makeFixture() throws -> (
        migrator: SQLiteRuntimeOperationLeaseLegacyMigrator,
        databaseURL: URL,
        sourceURL: URL,
        archiveURL: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteRuntimeOperationLeaseLegacyMigratorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let sourceURL = directory.appendingPathComponent("runtime-operation-lease.json")
        let archiveURL = directory.appendingPathComponent("runtime-operation-lease.legacy-migrated.json")
        return (
            SQLiteRuntimeOperationLeaseLegacyMigrator(
                databaseURL: databaseURL,
                sourceURL: sourceURL,
                archiveURL: archiveURL,
                timestamp: { "2026-07-14T05:00:00Z" }
            ),
            databaseURL,
            sourceURL,
            archiveURL
        )
    }

    private func lease(operationID: String) -> RuntimeOperationLeaseDocument {
        RuntimeOperationLeaseDocument(
            operationId: operationID,
            operation: .applyBundle,
            ownerPID: 321,
            startedAt: "2026-07-14T04:00:00Z",
            heartbeatAt: "2026-07-14T04:30:00Z",
            expiresAt: "2026-07-14T05:30:00Z",
            message: "legacy"
        )
    }

    private func scalarInt(_ url: URL, _ sql: String) throws -> Int {
        Int(try scalarString(url, sql) ?? "") ?? -1
    }

    private func scalarString(_ url: URL, _ sql: String) throws -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw TestFailure.sqlite("open failed")
        }
        defer { sqlite3_close(db) }
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

private enum TestFailure: Error {
    case sqlite(String)
}
