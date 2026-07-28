import Application
import Contracts
import Foundation
import SQLite3
import XCTest
@testable import Errors
@testable import OutboundAdapters

final class SQLiteHostRuntimeStateDatabaseTests: XCTestCase {
    func testMissingDatabaseReadinessDoesNotCreateDatabase() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)

        XCTAssertEqual(database.loadHostStateStoreReadiness(), .missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testInitializeCreatesVersionedDatabaseWithLeaseAndDiagnosticOutboxFoundation() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime/runtime-state.sqlite")
        let database = SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "host-db-1" },
            timestamp: { "2026-07-14T05:00:00Z" }
        )

        let metadata = try database.initialize()

        XCTAssertEqual(metadata, RuntimeHostStateStoreMetadata(
            schemaVersion: 10,
            databaseID: "host-db-1",
            createdAt: "2026-07-14T05:00:00Z",
            updatedAt: "2026-07-14T05:00:00Z"
        ))
        XCTAssertEqual(database.loadHostStateStoreReadiness(), .loaded(metadata))
        XCTAssertEqual(try tableNames(databaseURL), [
            "diagnostic_outbox",
            "diagnostic_projection_state",
            "host_runtime_settings",
            "installed_product_release",
            "legacy_state_imports",
            "runtime_endpoint",
            "runtime_metadata",
            "runtime_operation_lease",
            "schema_migrations",
            "sqlite_sequence",
            "update_bootstrap_journals",
            "vm_lifecycle",
            "workflow_operation_states",
        ])
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM schema_migrations"), 10)
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM diagnostic_outbox"), 0)
    }

    func testReopenPreservesDatabaseIdentityAndDoesNotReapplyMigration() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let first = SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "host-db-original" },
            timestamp: { "2026-07-14T05:00:00Z" }
        )
        _ = try first.initialize()
        let reopened = SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "host-db-must-not-replace" },
            timestamp: { "2099-01-01T00:00:00Z" }
        )

        let metadata = try reopened.initialize()

        XCTAssertEqual(metadata.databaseID, "host-db-original")
        XCTAssertEqual(metadata.createdAt, "2026-07-14T05:00:00Z")
        XCTAssertEqual(metadata.updatedAt, "2026-07-14T05:00:00Z")
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM schema_migrations"), 10)
    }

    func testInitializeUpgradesVersion1DatabaseToLatestWithoutReplacingIdentity() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        try createVersion1Database(databaseURL)
        let database = SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "must-not-replace-v1-identity" },
            timestamp: { "2026-07-14T06:00:00Z" }
        )

        let metadata = try database.initialize()

        XCTAssertEqual(metadata, RuntimeHostStateStoreMetadata(
            schemaVersion: 10,
            databaseID: "host-db-v1",
            createdAt: "2026-07-14T05:00:00Z",
            updatedAt: "2026-07-14T06:00:00Z"
        ))
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM schema_migrations"), 10)
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM runtime_operation_lease"), 0)
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM legacy_state_imports"), 0)
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM workflow_operation_states"), 0)
    }

    func testVersion10MigrationAssignsExplicitIdentityToVersion9Release() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent(
            "runtime-state.sqlite"
        )
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        try prepareVersion9InstalledRelease(databaseURL)

        let metadata = try SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            migratedInstallationID: { "installation-migrated-1" },
            timestamp: { "2026-07-29T00:00:00Z" }
        ).initialize()

        XCTAssertEqual(metadata.schemaVersion, 10)
        XCTAssertEqual(
            try scalarString(
                databaseURL,
                sql: """
                SELECT installation_id
                FROM installed_product_release
                WHERE singleton_id = 1
                """
            ),
            "installation-migrated-1"
        )
        XCTAssertEqual(
            try scalarInt(
                databaseURL,
                sql: """
                SELECT installation_revision
                FROM installed_product_release
                WHERE singleton_id = 1
                """
            ),
            1
        )
        let document = try XCTUnwrap(try scalarString(
            databaseURL,
            sql: """
            SELECT document_json
            FROM installed_product_release
            WHERE singleton_id = 1
            """
        ))
        let release = try JSONDecoder().decode(
            InstalledProductRelease.self,
            from: Data(document.utf8)
        )
        XCTAssertEqual(release.schemaVersion, "v2")
        XCTAssertEqual(release.installationId, "installation-migrated-1")
        XCTAssertEqual(release.installationRevision, 1)
        XCTAssertEqual(release.releaseRevision, 1)
    }

    func testVersion10MigrationRejectsInvalidExplicitIdentityAndRollsBack() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent(
            "runtime-state.sqlite"
        )
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        try prepareVersion9InstalledRelease(databaseURL)

        XCTAssertThrowsError(try SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            migratedInstallationID: { "" },
            timestamp: { "2026-07-29T00:00:00Z" }
        ).initialize()) { error in
            XCTAssertEqual(
                error as? SQLiteHostRuntimeStateDatabaseError,
                .installedProductReleaseMigrationInputInvalid(
                    field: "installationId",
                    value: ""
                )
            )
        }
        XCTAssertEqual(
            try scalarInt(
                databaseURL,
                sql: "SELECT schema_version FROM runtime_metadata"
            ),
            9
        )
        XCTAssertEqual(
            try scalarInt(
                databaseURL,
                sql: """
                SELECT COUNT(*)
                FROM pragma_table_info('installed_product_release')
                WHERE name = 'installation_id'
                """
            ),
            0
        )
    }

    func testReadinessReportsDirectoryPathAsFailureInsteadOfMissing() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        try FileManager.default.createDirectory(at: databaseURL, withIntermediateDirectories: false)
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)

        guard case .failed(let failure) = database.loadHostStateStoreReadiness() else {
            return XCTFail("expected failed readiness")
        }
        XCTAssertEqual(failure.stage, .pathInspection)
        XCTAssertTrue(failure.message.contains("state is unexpected"))
        XCTAssertThrowsError(try database.initialize()) { error in
            guard case SQLiteHostRuntimeStateDatabaseError.unexpectedPathState(let path, let state) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, databaseURL.path)
            XCTAssertEqual(state, "directory")
        }
    }

    func testReadinessReportsUninitializedSQLiteAsMigrationFailureWithoutMutatingIt() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        try withSQLiteDatabase(databaseURL) { _ in }
        let initialSize = try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)

        guard case .failed(let failure) = database.loadHostStateStoreReadiness() else {
            return XCTFail("expected failed readiness")
        }

        XCTAssertEqual(failure.stage, .migration)
        XCTAssertTrue(failure.message.contains("schema object is missing"))
        let finalSize = try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber
        XCTAssertEqual(finalSize, initialSize)
    }

    func testReadinessRejectsFutureSchemaVersion() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)
        _ = try database.initialize()
        try executeSQL(
            databaseURL,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (11, '2099-01-01T00:00:00Z')"
        )

        guard case .failed(let failure) = database.loadHostStateStoreReadiness() else {
            return XCTFail("expected failed readiness")
        }
        XCTAssertEqual(failure.stage, .migration)
        XCTAssertTrue(failure.message.contains("newer than this runtime"))
        XCTAssertThrowsError(try database.initialize()) { error in
            XCTAssertEqual(
                error as? SQLiteHostRuntimeStateDatabaseError,
                .unsupportedSchemaVersion(found: 11, supported: 10)
            )
        }
    }

    func testReadinessRejectsVersion7DatabaseMissingAppliedPayloadColumn() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)
        _ = try database.initialize()
        try executeSQL(
            databaseURL,
            sql: "ALTER TABLE host_runtime_settings DROP COLUMN applied_vm_config_json"
        )

        guard case .failed(let failure) = database.loadHostStateStoreReadiness() else {
            return XCTFail("expected failed readiness")
        }
        XCTAssertEqual(failure.stage, .migration)
        XCTAssertTrue(failure.message.contains("host_runtime_settings.applied_vm_config_json"))
    }

    func testVersion7MigrationInvalidatesUnprovableAppliedRevisionInsteadOfInferringPayload() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let database = SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            timestamp: { "2026-07-14T07:00:00Z" }
        )
        _ = try database.initialize()
        try executeSQL(databaseURL, sql: """
        INSERT INTO host_runtime_settings(
          singleton_id, revision, vm_config_json, guest_runtime_config_json,
          guest_runtime_settings_json, desired_at, materialized_revision,
          materialized_at, boot_revision, boot_run_id, boot_started_at,
          applied_revision, applied_run_id, applied_at
        ) VALUES (
          1, 2, '{}', '{}', '{}', 't2', 2, 't2', 2, 'run-2', 't2',
          1, 'run-1', 't1'
        )
        """)
        try executeSQL(databaseURL, sql: "DELETE FROM schema_migrations WHERE version >= 7")
        try executeSQL(databaseURL, sql: "UPDATE runtime_metadata SET schema_version = 6")
        try executeSQL(databaseURL, sql: "DROP TABLE installed_product_release")
        try executeSQL(databaseURL, sql: "DROP TABLE update_bootstrap_journals")
        try executeSQL(databaseURL, sql: "ALTER TABLE host_runtime_settings DROP COLUMN applied_vm_config_json")
        try executeSQL(databaseURL, sql: "ALTER TABLE host_runtime_settings DROP COLUMN applied_guest_runtime_config_json")
        try executeSQL(databaseURL, sql: "ALTER TABLE host_runtime_settings DROP COLUMN applied_guest_runtime_settings_json")

        let migrated = try SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            timestamp: { "2026-07-14T08:00:00Z" }
        ).initialize()

        XCTAssertEqual(migrated.schemaVersion, 10)
        XCTAssertEqual(
            try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM host_runtime_settings WHERE applied_revision IS NULL AND applied_run_id IS NULL AND applied_at IS NULL"),
            1
        )
    }

    func testReadinessPreservesCorruptDatabaseAsFailure() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        try Data("not-a-sqlite-database".utf8).write(to: databaseURL)
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)

        guard case .failed(let failure) = database.loadHostStateStoreReadiness() else {
            return XCTFail("expected failed readiness")
        }
        XCTAssertNotEqual(failure.stage, .pathInspection)
        XCTAssertFalse(failure.message.isEmpty)
    }

    func testReadinessReportsMissingMetadataWithoutCreatingDefaultState() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)
        _ = try database.initialize()
        try executeSQL(databaseURL, sql: "DELETE FROM runtime_metadata")

        guard case .failed(let failure) = database.loadHostStateStoreReadiness() else {
            return XCTFail("expected failed readiness")
        }
        XCTAssertEqual(failure.stage, .metadataRead)
        XCTAssertTrue(failure.message.contains("metadata row is missing"))
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM runtime_metadata"), 0)
    }

    func testImmediateTransactionRollsBackAllWritesAfterFailure() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)
        _ = try database.initialize()
        let connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: 100
        )

        XCTAssertThrowsError(try connection.withWritableDatabase { db in
            try connection.withImmediateTransaction(db) {
                try SQLiteHostRuntimeStateStatement.execute(
                    db,
                    sql: """
                    INSERT INTO diagnostic_outbox(
                      event_id,
                      aggregate_type,
                      aggregate_id,
                      aggregate_revision,
                      event_type,
                      occurred_at,
                      payload_json
                    ) VALUES ('event-1', 'test', 'aggregate-1', 1, 'changed', '2026-07-14T05:00:00Z', '{}')
                    """
                )
                throw TestFailure.expected
            }
        }) { error in
            XCTAssertEqual(error as? TestFailure, .expected)
        }
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM diagnostic_outbox"), 0)
    }

    func testImmediateTransactionReportsDatabaseLockWithoutWriting() throws {
        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("runtime-state.sqlite")
        let database = SQLiteHostRuntimeStateDatabase(url: databaseURL)
        _ = try database.initialize()

        try withSQLiteDatabase(databaseURL) { lockingDatabase in
            try rawExecute(lockingDatabase, sql: "BEGIN IMMEDIATE TRANSACTION")
            defer { try? rawExecute(lockingDatabase, sql: "ROLLBACK") }

            let competingConnection = SQLiteHostRuntimeStateConnection(
                url: databaseURL,
                busyTimeoutMilliseconds: 1
            )
            XCTAssertThrowsError(try competingConnection.withWritableDatabase { db in
                try competingConnection.withImmediateTransaction(db) {}
            }) { error in
                guard case SQLiteHostRuntimeStateDatabaseError.stepFailed(let reason) = error else {
                    return XCTFail("unexpected error: \(error)")
                }
                XCTAssertTrue(reason.lowercased().contains("locked"))
            }
        }
        XCTAssertEqual(try scalarInt(databaseURL, sql: "SELECT COUNT(*) FROM diagnostic_outbox"), 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteHostRuntimeStateDatabaseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func tableNames(_ url: URL) throws -> [String] {
        try withSQLiteDatabase(url, readOnly: true) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
                -1,
                &statement,
                nil
            ) == SQLITE_OK else {
                throw TestFailure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            var names: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let value = sqlite3_column_text(statement, 0) {
                    names.append(String(cString: value))
                }
            }
            return names
        }
    }

    private func scalarInt(_ url: URL, sql: String) throws -> Int {
        try withSQLiteDatabase(url, readOnly: true) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TestFailure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw TestFailure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func scalarString(_ url: URL, sql: String) throws -> String? {
        try withSQLiteDatabase(url, readOnly: true) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                sql,
                -1,
                &statement,
                nil
            ) == SQLITE_OK else {
                throw TestFailure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw TestFailure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            guard let value = sqlite3_column_text(statement, 0) else {
                return nil
            }
            return String(cString: value)
        }
    }

    private func executeSQL(_ url: URL, sql: String) throws {
        try withSQLiteDatabase(url) { db in
            try rawExecute(db, sql: sql)
        }
    }

    private func createVersion1Database(_ url: URL) throws {
        try withSQLiteDatabase(url) { db in
            try rawExecute(db, sql: """
            CREATE TABLE schema_migrations (
              version INTEGER PRIMARY KEY,
              applied_at TEXT NOT NULL CHECK(length(applied_at) > 0)
            );
            CREATE TABLE runtime_metadata (
              singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
              schema_version INTEGER NOT NULL CHECK(schema_version > 0),
              database_id TEXT NOT NULL UNIQUE CHECK(length(database_id) > 0),
              created_at TEXT NOT NULL CHECK(length(created_at) > 0),
              updated_at TEXT NOT NULL CHECK(length(updated_at) > 0)
            );
            CREATE TABLE diagnostic_outbox (
              sequence INTEGER PRIMARY KEY AUTOINCREMENT,
              event_id TEXT NOT NULL UNIQUE CHECK(length(event_id) > 0),
              aggregate_type TEXT NOT NULL CHECK(length(aggregate_type) > 0),
              aggregate_id TEXT NOT NULL CHECK(length(aggregate_id) > 0),
              aggregate_revision INTEGER NOT NULL CHECK(aggregate_revision > 0),
              event_type TEXT NOT NULL CHECK(length(event_type) > 0),
              occurred_at TEXT NOT NULL CHECK(length(occurred_at) > 0),
              payload_json TEXT NOT NULL CHECK(length(payload_json) > 0),
              projected_at TEXT,
              projection_attempts INTEGER NOT NULL DEFAULT 0 CHECK(projection_attempts >= 0),
              last_projection_error TEXT
            );
            CREATE INDEX idx_diagnostic_outbox_pending
              ON diagnostic_outbox(projected_at, sequence);
            CREATE TABLE diagnostic_projection_state (
              projection_name TEXT PRIMARY KEY CHECK(length(projection_name) > 0),
              last_sequence INTEGER NOT NULL CHECK(last_sequence >= 0),
              updated_at TEXT NOT NULL CHECK(length(updated_at) > 0)
            );
            INSERT INTO runtime_metadata(
              singleton_id, schema_version, database_id, created_at, updated_at
            ) VALUES (
              1, 1, 'host-db-v1', '2026-07-14T05:00:00Z', '2026-07-14T05:00:00Z'
            );
            INSERT INTO schema_migrations(version, applied_at)
              VALUES (1, '2026-07-14T05:00:00Z');
            """)
        }
    }

    private func prepareVersion9InstalledRelease(_ url: URL) throws {
        try executeSQL(url, sql: """
        DELETE FROM schema_migrations WHERE version = 10;
        UPDATE runtime_metadata SET schema_version = 9;
        DROP TABLE installed_product_release;
        CREATE TABLE installed_product_release (
          singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
          release_revision INTEGER NOT NULL CHECK(release_revision > 0),
          source TEXT NOT NULL CHECK(source IN ('package-install', 'update')),
          document_json TEXT NOT NULL CHECK(length(document_json) > 0),
          settled_at TEXT NOT NULL CHECK(length(settled_at) > 0)
        );
        INSERT INTO installed_product_release(
          singleton_id,
          release_revision,
          source,
          document_json,
          settled_at
        ) VALUES (
          1,
          1,
          'package-install',
          '{"schemaVersion":"v1","productId":"ai.tirosh.vitalserver.helper","productVersion":"0.2.2","runtimeVersion":"0.2.2","releaseRevision":1,"source":"package-install","installOperationId":"install-1","settledAt":"2026-07-27T00:00:00Z"}',
          '2026-07-27T00:00:00Z'
        );
        """)
    }

    private func rawExecute(_ db: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw TestFailure.sqlite(message)
        }
    }

    private func withSQLiteDatabase<T>(
        _ url: URL,
        readOnly: Bool = false,
        operation: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK,
              let openedDatabase = database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite open failed"
            sqlite3_close(database)
            throw TestFailure.sqlite(message)
        }
        defer { sqlite3_close(openedDatabase) }
        return try operation(openedDatabase)
    }
}

private enum TestFailure: Error, Equatable {
    case expected
    case sqlite(String)
}
