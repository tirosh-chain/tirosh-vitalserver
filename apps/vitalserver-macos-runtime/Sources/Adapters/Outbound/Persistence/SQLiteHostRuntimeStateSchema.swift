import Application
import Contracts
import Errors
import Foundation
import SQLite3

enum SQLiteHostRuntimeStateSchema {
    static let supportedVersion = 11

    static func migrate(
        _ db: OpaquePointer,
        connection: SQLiteHostRuntimeStateConnection,
        databaseID: () -> String,
        migratedInstallationID: () -> String,
        timestamp: () -> String
    ) throws -> RuntimeHostStateStoreMetadata {
        try connection.withImmediateTransaction(db) {
            try SQLiteHostRuntimeStateStatement.execute(db, sql: """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY,
              applied_at TEXT NOT NULL CHECK(length(applied_at) > 0)
            )
            """)

            let appliedVersions = try SQLiteHostRuntimeStateStatement.integerRows(
                db,
                sql: "SELECT version FROM schema_migrations ORDER BY version"
            )
            try validateMigrationSequence(appliedVersions)
            let currentVersion = appliedVersions.last ?? 0
            guard currentVersion <= supportedVersion else {
                throw SQLiteHostRuntimeStateDatabaseError.unsupportedSchemaVersion(
                    found: currentVersion,
                    supported: supportedVersion
                )
            }

            if currentVersion < 1 {
                try applyVersion1(
                    db,
                    databaseID: databaseID(),
                    appliedAt: timestamp()
                )
            }
            if currentVersion < 2 {
                try applyVersion2(db, appliedAt: timestamp())
            }
            if currentVersion < 3 {
                try applyVersion3(db, appliedAt: timestamp())
            }
            if currentVersion < 4 {
                try applyVersion4(db, appliedAt: timestamp())
            }
            if currentVersion < 5 {
                try applyVersion5(db, appliedAt: timestamp())
            }
            if currentVersion < 6 {
                try applyVersion6(db, appliedAt: timestamp())
            }
            if currentVersion < 7 {
                try applyVersion7(db, appliedAt: timestamp())
            }
            if currentVersion < 8 {
                try applyVersion8(db, appliedAt: timestamp())
            }
            if currentVersion < 9 {
                try applyVersion9(db, appliedAt: timestamp())
            }
            if currentVersion < 10 {
                try applyVersion10(
                    db,
                    migratedInstallationID: migratedInstallationID,
                    appliedAt: timestamp()
                )
            }
            if currentVersion < 11 {
                try applyVersion11(db, appliedAt: timestamp())
            }

            return try loadMetadata(db)
        }
    }

    static func validate(_ db: OpaquePointer) throws -> RuntimeHostStateStoreMetadata {
        let integrityResult = try SQLiteHostRuntimeStateStatement.scalarString(
            db,
            sql: "PRAGMA integrity_check"
        )
        guard integrityResult == "ok" else {
            throw SQLiteHostRuntimeStateDatabaseError.integrityCheckFailed(
                integrityResult ?? "missing"
            )
        }

        for table in [
            "schema_migrations",
            "runtime_metadata",
            "diagnostic_outbox",
            "diagnostic_projection_state",
            "legacy_state_imports",
            "runtime_operation_lease",
            "workflow_operation_states",
            "vm_lifecycle",
            "runtime_endpoint",
            "host_runtime_settings",
            "update_bootstrap_journals",
            "installed_product_release",
        ] {
            let count = try SQLiteHostRuntimeStateStatement.scalarInt(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                bindings: [.text(table)]
            )
            guard count == 1 else {
                throw SQLiteHostRuntimeStateDatabaseError.schemaObjectMissing(table)
            }
        }

        let appliedVersions = try SQLiteHostRuntimeStateStatement.integerRows(
            db,
            sql: "SELECT version FROM schema_migrations ORDER BY version"
        )
        try validateMigrationSequence(appliedVersions)
        let currentVersion = appliedVersions.last ?? 0
        guard currentVersion <= supportedVersion else {
            throw SQLiteHostRuntimeStateDatabaseError.unsupportedSchemaVersion(
                found: currentVersion,
                supported: supportedVersion
            )
        }
        guard currentVersion == supportedVersion else {
            throw SQLiteHostRuntimeStateDatabaseError.migrationSequenceInvalid(
                expected: supportedVersion,
                actual: currentVersion
            )
        }

        try requireColumns(
            db,
            table: "diagnostic_projection_state",
            columns: ["failure_attempts", "last_error"]
        )
        try requireColumns(
            db,
            table: "host_runtime_settings",
            columns: [
                "applied_vm_config_json",
                "applied_guest_runtime_config_json",
                "applied_guest_runtime_settings_json",
            ]
        )
        try requireColumns(
            db,
            table: "installed_product_release",
            columns: [
                "installation_id",
                "installation_revision",
                "release_revision",
            ]
        )
        try requireColumns(
            db,
            table: "runtime_operation_lease",
            columns: [
                "target_installation_id",
                "expected_installation_revision",
            ]
        )

        let metadata = try loadMetadata(db)
        guard metadata.schemaVersion == currentVersion else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "schemaVersion",
                value: String(metadata.schemaVersion)
            )
        }
        return metadata
    }

    private static func requireColumns(
        _ db: OpaquePointer,
        table: String,
        columns: [String]
    ) throws {
        for column in columns {
            let count = try SQLiteHostRuntimeStateStatement.scalarInt(
                db,
                sql: "SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?",
                bindings: [.text(table), .text(column)]
            )
            guard count == 1 else {
                throw SQLiteHostRuntimeStateDatabaseError.schemaObjectMissing("\(table).\(column)")
            }
        }
    }

    private static func applyVersion1(
        _ db: OpaquePointer,
        databaseID: String,
        appliedAt: String
    ) throws {
        guard !databaseID.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "databaseID",
                value: databaseID
            )
        }
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }

        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE TABLE runtime_metadata (
          singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
          schema_version INTEGER NOT NULL CHECK(schema_version > 0),
          database_id TEXT NOT NULL UNIQUE CHECK(length(database_id) > 0),
          created_at TEXT NOT NULL CHECK(length(created_at) > 0),
          updated_at TEXT NOT NULL CHECK(length(updated_at) > 0)
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
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
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE INDEX idx_diagnostic_outbox_pending
          ON diagnostic_outbox(projected_at, sequence)
        """)
        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE TABLE diagnostic_projection_state (
          projection_name TEXT PRIMARY KEY CHECK(length(projection_name) > 0),
          last_sequence INTEGER NOT NULL CHECK(last_sequence >= 0),
          updated_at TEXT NOT NULL CHECK(length(updated_at) > 0)
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            INSERT INTO runtime_metadata(
              singleton_id,
              schema_version,
              database_id,
              created_at,
              updated_at
            ) VALUES (1, ?, ?, ?, ?)
            """,
            bindings: [
                .int(1),
                .text(databaseID),
                .text(appliedAt),
                .text(appliedAt),
            ]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(1), .text(appliedAt)]
        )
    }

    private static func applyVersion2(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }

        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE TABLE runtime_operation_lease (
          singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
          revision INTEGER NOT NULL CHECK(revision > 0),
          state TEXT NOT NULL CHECK(state IN ('active', 'released')),
          document_schema_version INTEGER NOT NULL CHECK(document_schema_version > 0),
          operation_id TEXT NOT NULL CHECK(length(operation_id) > 0),
          operation TEXT NOT NULL CHECK(length(operation) > 0),
          owner_pid INTEGER,
          started_at TEXT NOT NULL CHECK(length(started_at) > 0),
          heartbeat_at TEXT NOT NULL CHECK(length(heartbeat_at) > 0),
          expires_at TEXT,
          message TEXT,
          updated_at TEXT NOT NULL CHECK(length(updated_at) > 0)
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE TABLE legacy_state_imports (
          migration_id TEXT PRIMARY KEY CHECK(length(migration_id) > 0),
          source_path TEXT NOT NULL CHECK(length(source_path) > 0),
          source_state TEXT NOT NULL CHECK(source_state IN ('missing', 'imported')),
          source_operation_id TEXT,
          completed_at TEXT NOT NULL CHECK(length(completed_at) > 0),
          CHECK(
            (source_state = 'missing' AND source_operation_id IS NULL)
            OR (source_state = 'imported' AND length(source_operation_id) > 0)
          )
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 2, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(2), .text(appliedAt)]
        )
    }

    private static func applyVersion3(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }

        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE TABLE workflow_operation_states (
          operation_id TEXT PRIMARY KEY CHECK(length(operation_id) > 0),
          operation_type TEXT NOT NULL CHECK(length(operation_type) > 0),
          phase TEXT NOT NULL CHECK(length(phase) > 0),
          current_step TEXT,
          step_status TEXT,
          message TEXT NOT NULL CHECK(length(message) > 0),
          reason_codes_json TEXT NOT NULL CHECK(length(reason_codes_json) > 0),
          started_at TEXT NOT NULL CHECK(length(started_at) > 0),
          updated_at TEXT NOT NULL CHECK(length(updated_at) > 0),
          completed_at TEXT,
          revision INTEGER NOT NULL CHECK(revision > 0),
          CHECK(
            (current_step IS NULL AND step_status IS NULL)
            OR (length(current_step) > 0 AND length(step_status) > 0)
          )
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE INDEX idx_workflow_operation_states_latest
          ON workflow_operation_states(operation_type, updated_at DESC, revision DESC)
        """)
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 3, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(3), .text(appliedAt)]
        )
    }

    private static func applyVersion4(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }

        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE TABLE vm_lifecycle (
          singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
          revision INTEGER NOT NULL CHECK(revision > 0),
          document_schema_version INTEGER NOT NULL CHECK(document_schema_version > 0),
          run_id TEXT NOT NULL CHECK(length(run_id) > 0),
          state TEXT NOT NULL CHECK(state IN (
            'starting', 'bootstrapping', 'running', 'stopping', 'stopped', 'failed'
          )),
          operation TEXT NOT NULL CHECK(length(operation) > 0),
          operation_id TEXT NOT NULL CHECK(length(operation_id) > 0),
          started_at TEXT NOT NULL CHECK(length(started_at) > 0),
          updated_at TEXT NOT NULL CHECK(length(updated_at) > 0),
          deadline_at TEXT,
          terminal_reason TEXT,
          message TEXT,
          CHECK(state = 'failed' OR terminal_reason IS NULL)
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE TABLE runtime_endpoint (
          singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
          revision INTEGER NOT NULL CHECK(revision > 0),
          run_id TEXT NOT NULL CHECK(length(run_id) > 0),
          lifecycle_revision INTEGER NOT NULL CHECK(lifecycle_revision > 0),
          address TEXT NOT NULL CHECK(length(address) > 0),
          source TEXT NOT NULL CHECK(source = 'platform-agent'),
          observed_at TEXT NOT NULL CHECK(length(observed_at) > 0)
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 4, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(4), .text(appliedAt)]
        )
    }

    private static func applyVersion5(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }

        try SQLiteHostRuntimeStateStatement.execute(db, sql: """
        CREATE TABLE host_runtime_settings (
          singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
          revision INTEGER NOT NULL CHECK(revision > 0),
          vm_config_json TEXT NOT NULL CHECK(length(vm_config_json) > 0),
          guest_runtime_config_json TEXT NOT NULL CHECK(length(guest_runtime_config_json) > 0),
          guest_runtime_settings_json TEXT NOT NULL CHECK(length(guest_runtime_settings_json) > 0),
          desired_at TEXT NOT NULL CHECK(length(desired_at) > 0),
          materialized_revision INTEGER,
          materialized_at TEXT,
          boot_revision INTEGER,
          boot_run_id TEXT,
          boot_started_at TEXT,
          applied_revision INTEGER,
          applied_run_id TEXT,
          applied_at TEXT,
          CHECK(materialized_revision IS NULL OR materialized_revision = revision),
          CHECK(
            (materialized_revision IS NULL AND materialized_at IS NULL)
            OR (materialized_revision = revision AND length(materialized_at) > 0)
          ),
          CHECK(
            (boot_revision IS NULL AND boot_run_id IS NULL AND boot_started_at IS NULL)
            OR (
              boot_revision = materialized_revision
              AND length(boot_run_id) > 0
              AND length(boot_started_at) > 0
            )
          ),
          CHECK(
            (applied_revision IS NULL AND applied_run_id IS NULL AND applied_at IS NULL)
            OR (
              applied_revision <= revision
              AND length(applied_run_id) > 0
              AND length(applied_at) > 0
            )
          )
        )
        """)
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 5, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(5), .text(appliedAt)]
        )
    }

    private static func applyVersion6(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "ALTER TABLE diagnostic_projection_state ADD COLUMN failure_attempts INTEGER NOT NULL DEFAULT 0 CHECK(failure_attempts >= 0)"
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "ALTER TABLE diagnostic_projection_state ADD COLUMN last_error TEXT"
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 6, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(6), .text(appliedAt)]
        )
    }

    private static func applyVersion7(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }

        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "ALTER TABLE host_runtime_settings ADD COLUMN applied_vm_config_json TEXT"
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "ALTER TABLE host_runtime_settings ADD COLUMN applied_guest_runtime_config_json TEXT"
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "ALTER TABLE host_runtime_settings ADD COLUMN applied_guest_runtime_settings_json TEXT"
        )

        // Schema v6 retained only the applied revision, not the payload that revision
        // represented. The migration must not infer that payload from mutable files or
        // from the current desired payload. Invalidate the unprovable application proof
        // so the next explicit VM boot and health proof can establish it again.
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE host_runtime_settings
            SET applied_revision = NULL, applied_run_id = NULL, applied_at = NULL
            WHERE applied_revision IS NOT NULL
            """
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 7, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(7), .text(appliedAt)]
        )
    }

    private static func applyVersion8(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            CREATE TABLE update_bootstrap_journals (
              journal_id TEXT PRIMARY KEY CHECK(length(journal_id) > 0),
              journal_revision INTEGER NOT NULL CHECK(journal_revision > 0),
              state TEXT NOT NULL CHECK(length(state) > 0),
              document_json TEXT NOT NULL CHECK(length(document_json) > 0),
              updated_at TEXT NOT NULL CHECK(length(updated_at) > 0)
            )
            """
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            CREATE INDEX idx_update_bootstrap_journals_latest
              ON update_bootstrap_journals(updated_at DESC, journal_revision DESC)
            """
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 8, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(8), .text(appliedAt)]
        )
    }

    private static func applyVersion9(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            CREATE TABLE installed_product_release (
              singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
              release_revision INTEGER NOT NULL CHECK(release_revision > 0),
              source TEXT NOT NULL CHECK(source IN ('package-install', 'update')),
              document_json TEXT NOT NULL CHECK(length(document_json) > 0),
              settled_at TEXT NOT NULL CHECK(length(settled_at) > 0)
            )
            """
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 9, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(9), .text(appliedAt)]
        )
    }

    private static func applyVersion10(
        _ db: OpaquePointer,
        migratedInstallationID: () -> String,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }

        let migratedRelease = try loadVersion9InstalledRelease(
            db,
            migratedInstallationID: migratedInstallationID
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            CREATE TABLE installed_product_release_v10 (
              singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
              installation_id TEXT NOT NULL CHECK(length(installation_id) > 0),
              installation_revision INTEGER NOT NULL CHECK(installation_revision > 0),
              release_revision INTEGER NOT NULL CHECK(release_revision > 0),
              source TEXT NOT NULL CHECK(source IN ('package-install', 'update')),
              document_json TEXT NOT NULL CHECK(length(document_json) > 0),
              settled_at TEXT NOT NULL CHECK(length(settled_at) > 0)
            )
            """
        )
        if let migratedRelease {
            let document: String
            do {
                document = String(
                    decoding: try JSONEncoder().encode(migratedRelease),
                    as: UTF8.self
                )
            } catch {
                throw SQLiteHostRuntimeStateDatabaseError
                    .installedProductReleaseMigrationDocumentInvalid(
                        reason: "v2 encode failed: \(error)"
                    )
            }
            try SQLiteHostRuntimeStateStatement.execute(
                db,
                sql: """
                INSERT INTO installed_product_release_v10(
                  singleton_id,
                  installation_id,
                  installation_revision,
                  release_revision,
                  source,
                  document_json,
                  settled_at
                ) VALUES (1, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(migratedRelease.installationId),
                    .int(migratedRelease.installationRevision),
                    .int(migratedRelease.releaseRevision),
                    .text(migratedRelease.source.rawValue),
                    .text(document),
                    .text(migratedRelease.settledAt),
                ]
            )
        }
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "DROP TABLE installed_product_release"
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            ALTER TABLE installed_product_release_v10
            RENAME TO installed_product_release
            """
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 10, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(10), .text(appliedAt)]
        )
    }

    private static func applyVersion11(
        _ db: OpaquePointer,
        appliedAt: String
    ) throws {
        guard !appliedAt.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "appliedAt",
                value: appliedAt
            )
        }
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "ALTER TABLE runtime_operation_lease ADD COLUMN target_installation_id TEXT"
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "ALTER TABLE runtime_operation_lease ADD COLUMN expected_installation_revision INTEGER"
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE runtime_metadata
            SET schema_version = 11, updated_at = ?
            WHERE singleton_id = 1
            """,
            bindings: [.text(appliedAt)]
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(11), .text(appliedAt)]
        )
    }

    private static func loadVersion9InstalledRelease(
        _ db: OpaquePointer,
        migratedInstallationID: () -> String
    ) throws -> InstalledProductRelease? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT release_revision, source, document_json, settled_at
            FROM installed_product_release
            WHERE singleton_id = 1
            """,
            columnCount: 4
        ) else {
            return nil
        }
        let rowReleaseRevision = try requiredMigrationInt(
            row[0],
            field: "release_revision"
        )
        let rowSource = try requiredMigrationText(
            row[1],
            field: "source"
        )
        let document = try requiredMigrationText(
            row[2],
            field: "document_json"
        )
        let rowSettledAt = try requiredMigrationText(
            row[3],
            field: "settled_at"
        )

        let legacy: Version9InstalledProductReleaseDocument
        do {
            legacy = try JSONDecoder().decode(
                Version9InstalledProductReleaseDocument.self,
                from: Data(document.utf8)
            )
        } catch {
            throw SQLiteHostRuntimeStateDatabaseError
                .installedProductReleaseMigrationDocumentInvalid(
                    reason: "v1 decode failed: \(error)"
                )
        }
        try validateVersion9InstalledRelease(
            legacy,
            rowReleaseRevision: rowReleaseRevision,
            rowSource: rowSource,
            rowSettledAt: rowSettledAt
        )

        let installationID = migratedInstallationID()
        guard isMigrationIdentifier(installationID) else {
            throw SQLiteHostRuntimeStateDatabaseError
                .installedProductReleaseMigrationInputInvalid(
                    field: "installationId",
                    value: installationID
                )
        }
        return InstalledProductRelease(
            schemaVersion: "v2",
            installationId: installationID,
            installationRevision: legacy.releaseRevision,
            productId: legacy.productId,
            productVersion: legacy.productVersion,
            runtimeVersion: legacy.runtimeVersion,
            releaseRevision: legacy.releaseRevision,
            source: legacy.source,
            installOperationId: legacy.installOperationId,
            updateId: legacy.updateId,
            journalId: legacy.journalId,
            journalRevision: legacy.journalRevision,
            reportRelativePath: legacy.reportRelativePath,
            reportSHA256: legacy.reportSHA256,
            settledAt: legacy.settledAt
        )
    }

    private static func validateVersion9InstalledRelease(
        _ release: Version9InstalledProductReleaseDocument,
        rowReleaseRevision: Int,
        rowSource: String,
        rowSettledAt: String
    ) throws {
        guard release.schemaVersion == "v1" else {
            throw migrationDocumentInvalid(
                "schemaVersion=\(release.schemaVersion)"
            )
        }
        guard isMigrationIdentifier(release.productId),
              isMigrationVersion(release.productVersion),
              isMigrationVersion(release.runtimeVersion),
              release.releaseRevision > 0,
              isMigrationTimestamp(release.settledAt) else {
            throw migrationDocumentInvalid("required field is invalid")
        }
        guard release.releaseRevision == rowReleaseRevision,
              release.source.rawValue == rowSource,
              release.settledAt == rowSettledAt else {
            throw migrationDocumentInvalid(
                "row metadata does not match document"
            )
        }
        switch release.source {
        case .packageInstall:
            guard release.releaseRevision == 1,
                  release.installOperationId.map(isMigrationIdentifier) == true,
                  release.updateId == nil,
                  release.journalId == nil,
                  release.journalRevision == nil,
                  release.reportRelativePath == nil,
                  release.reportSHA256 == nil else {
                throw migrationDocumentInvalid(
                    "package-install evidence is invalid"
                )
            }
        case .update:
            guard release.installOperationId == nil,
                  release.releaseRevision > 1,
                  release.updateId.map(isMigrationIdentifier) == true,
                  release.journalId.map(isMigrationIdentifier) == true,
                  release.journalRevision.map({ $0 > 0 }) == true,
                  release.reportRelativePath
                    .map(isMigrationSafeRelativePath) == true,
                  release.reportSHA256.map(isMigrationSHA256) == true else {
                throw migrationDocumentInvalid("update evidence is invalid")
            }
        }
    }

    private static func requiredMigrationText(
        _ value: String?,
        field: String
    ) throws -> String {
        guard let value, !value.isEmpty else {
            throw migrationDocumentInvalid(
                "row field \(field) is NULL or empty"
            )
        }
        return value
    }

    private static func requiredMigrationInt(
        _ value: String?,
        field: String
    ) throws -> Int {
        guard let value, let parsed = Int(value) else {
            throw migrationDocumentInvalid(
                "row field \(field) is not an integer"
            )
        }
        return parsed
    }

    private static func isMigrationIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 128
            && value.unicodeScalars.allSatisfy { scalar in
                let code = scalar.value
                return (65...90).contains(code)
                    || (97...122).contains(code)
                    || (48...57).contains(code)
                    || "-._".unicodeScalars.contains(scalar)
            }
    }

    private static func isMigrationVersion(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 128
            && value.unicodeScalars.allSatisfy { scalar in
                let code = scalar.value
                return (65...90).contains(code)
                    || (97...122).contains(code)
                    || (48...57).contains(code)
                    || ".+-_".unicodeScalars.contains(scalar)
            }
    }

    private static func isMigrationTimestamp(_ value: String) -> Bool {
        guard value.count == 20, value.hasSuffix("Z") else {
            return false
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }

    private static func isMigrationSafeRelativePath(
        _ value: String
    ) -> Bool {
        let parts = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !value.isEmpty
            && !value.hasPrefix("/")
            && !value.contains("\\")
            && !parts.contains {
                $0.isEmpty || $0 == "." || $0 == ".."
            }
    }

    private static func isMigrationSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func migrationDocumentInvalid(
        _ reason: String
    ) -> SQLiteHostRuntimeStateDatabaseError {
        .installedProductReleaseMigrationDocumentInvalid(reason: reason)
    }

    private static func validateMigrationSequence(_ versions: [Int]) throws {
        for (offset, version) in versions.enumerated() {
            let expected = offset + 1
            guard version == expected else {
                throw SQLiteHostRuntimeStateDatabaseError.migrationSequenceInvalid(
                    expected: expected,
                    actual: version
                )
            }
        }
    }

    private static func loadMetadata(
        _ db: OpaquePointer
    ) throws -> RuntimeHostStateStoreMetadata {
        let rowCount = try SQLiteHostRuntimeStateStatement.scalarInt(
            db,
            sql: "SELECT COUNT(*) FROM runtime_metadata WHERE singleton_id = 1"
        )
        guard rowCount == 1 else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataMissing
        }

        guard let schemaVersion = try SQLiteHostRuntimeStateStatement.scalarInt(
            db,
            sql: "SELECT schema_version FROM runtime_metadata WHERE singleton_id = 1"
        ) else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: "schemaVersion",
                value: "NULL"
            )
        }
        let databaseID = try requiredMetadataText(db, column: "database_id")
        let createdAt = try requiredMetadataText(db, column: "created_at")
        let updatedAt = try requiredMetadataText(db, column: "updated_at")
        return RuntimeHostStateStoreMetadata(
            schemaVersion: schemaVersion,
            databaseID: databaseID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func requiredMetadataText(
        _ db: OpaquePointer,
        column: String
    ) throws -> String {
        guard let value = try SQLiteHostRuntimeStateStatement.scalarString(
            db,
            sql: "SELECT \(column) FROM runtime_metadata WHERE singleton_id = 1"
        ), !value.isEmpty else {
            throw SQLiteHostRuntimeStateDatabaseError.metadataInvalid(
                field: column,
                value: "NULL-or-empty"
            )
        }
        return value
    }
}

private struct Version9InstalledProductReleaseDocument: Decodable {
    let schemaVersion: String
    let productId: String
    let productVersion: String
    let runtimeVersion: String
    let releaseRevision: Int
    let source: InstalledProductReleaseSource
    let installOperationId: String?
    let updateId: String?
    let journalId: String?
    let journalRevision: Int?
    let reportRelativePath: String?
    let reportSHA256: String?
    let settledAt: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case productId
        case productVersion
        case runtimeVersion
        case releaseRevision
        case source
        case installOperationId
        case updateId
        case journalId
        case journalRevision
        case reportRelativePath
        case reportSHA256
        case settledAt
    }

    init(from decoder: Decoder) throws {
        let allKeys = try decoder
            .container(keyedBy: Version9InstalledProductReleaseDynamicKey.self)
            .allKeys
            .map(\.stringValue)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = allKeys.filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription:
                    "Version9InstalledProductReleaseDocument contains unknown keys: \(unknown.joined(separator: ","))"
            ))
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        productId = try container.decode(String.self, forKey: .productId)
        productVersion = try container.decode(
            String.self,
            forKey: .productVersion
        )
        runtimeVersion = try container.decode(
            String.self,
            forKey: .runtimeVersion
        )
        releaseRevision = try container.decode(
            Int.self,
            forKey: .releaseRevision
        )
        source = try container.decode(
            InstalledProductReleaseSource.self,
            forKey: .source
        )
        installOperationId = try container.decodeIfPresent(
            String.self,
            forKey: .installOperationId
        )
        updateId = try container.decodeIfPresent(
            String.self,
            forKey: .updateId
        )
        journalId = try container.decodeIfPresent(
            String.self,
            forKey: .journalId
        )
        journalRevision = try container.decodeIfPresent(
            Int.self,
            forKey: .journalRevision
        )
        reportRelativePath = try container.decodeIfPresent(
            String.self,
            forKey: .reportRelativePath
        )
        reportSHA256 = try container.decodeIfPresent(
            String.self,
            forKey: .reportSHA256
        )
        settledAt = try container.decode(String.self, forKey: .settledAt)
    }
}

private struct Version9InstalledProductReleaseDynamicKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
