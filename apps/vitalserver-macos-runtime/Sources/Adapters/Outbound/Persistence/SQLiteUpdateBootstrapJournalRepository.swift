import Application
import Contracts
import Foundation

public enum SQLiteUpdateBootstrapJournalRepositoryError:
    Error,
    Equatable,
    Sendable
{
    case invalidJournal(reason: String)
    case invalidInstalledRelease(reason: String)
    case installedReleaseAlreadyExists(
        installationId: String,
        installationRevision: Int
    )
    case installedReleaseMissing
    case installedReleaseIdentityMismatch(expected: String, actual: String)
    case staleInstallationRevision(expected: Int, actual: Int)
    case settlementInstallationRevisionMismatch(journal: Int, caller: Int)
    case operationLeaseMissing
    case operationLeaseNotActive(state: String)
    case operationLeaseMismatch(field: String, expected: String, actual: String)
    case installedReleaseCASFailed(
        installationId: String,
        expectedInstallationRevision: Int,
        expectedReleaseRevision: Int
    )
    case missing(id: String)
    case alreadyExists(id: String, revision: Int)
    case staleRevision(id: String, expected: Int, actual: Int)
    case invalidNextRevision(id: String, expected: Int, actual: Int)
    case writeFailed(path: String, reason: String)
}

public struct SQLiteUpdateBootstrapJournalRepository:
    UpdateBootstrapJournalRepository,
    InstalledProductReleaseReading,
    PackageInstallReleaseWriting,
    SucceededUpdateSettlementWriting,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let validate: (UpdateBootstrapJournal) throws -> Void
    private let validateRelease: (InstalledProductRelease) throws -> Void
    private let validateSettlement: (
        InstalledProductRelease,
        UpdateBootstrapJournal
    ) throws -> Void

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        validate: @escaping (UpdateBootstrapJournal) throws -> Void,
        validateRelease: @escaping (InstalledProductRelease) throws -> Void,
        validateSettlement: @escaping (
            InstalledProductRelease,
            UpdateBootstrapJournal
        ) throws -> Void
    ) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.encoder = encoder
        self.decoder = decoder
        self.validate = validate
        self.validateRelease = validateRelease
        self.validateSettlement = validateSettlement
    }

    public func loadUpdateBootstrapJournal(
        id: String
    ) -> UpdateBootstrapJournalReadResult {
        guard !id.isEmpty else {
            return .failed(reason: "update bootstrap journal id is empty")
        }
        return read(
            sql: """
            SELECT document_json
            FROM update_bootstrap_journals
            WHERE journal_id = ?
            """,
            bindings: [.text(id)]
        )
    }

    public func loadLatestUpdateBootstrapJournal(
    ) -> UpdateBootstrapJournalReadResult {
        read(
            sql: """
            SELECT document_json
            FROM update_bootstrap_journals
            ORDER BY updated_at DESC, journal_revision DESC
            LIMIT 1
            """,
            bindings: []
        )
    }

    public func saveUpdateBootstrapJournal(
        _ journal: UpdateBootstrapJournal,
        expectedRevision: Int?
    ) throws {
        do {
            try validate(journal)
        } catch {
            throw SQLiteUpdateBootstrapJournalRepositoryError.invalidJournal(
                reason: String(describing: error)
            )
        }

        do {
            try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                try connection.withImmediateTransaction(db) {
                    let existingRevision = try SQLiteHostRuntimeStateStatement.scalarInt(
                        db,
                        sql: """
                        SELECT journal_revision
                        FROM update_bootstrap_journals
                        WHERE journal_id = ?
                        """,
                        bindings: [.text(journal.id)]
                    )
                    try validateRevision(
                        id: journal.id,
                        journalRevision: journal.journalRevision,
                        expectedRevision: expectedRevision,
                        existingRevision: existingRevision
                    )
                    let document = String(
                        decoding: try encoder.encode(journal),
                        as: UTF8.self
                    )
                    if existingRevision == nil {
                        try SQLiteHostRuntimeStateStatement.execute(
                            db,
                            sql: """
                            INSERT INTO update_bootstrap_journals(
                              journal_id,
                              journal_revision,
                              state,
                              document_json,
                              updated_at
                            ) VALUES (?, ?, ?, ?, ?)
                            """,
                            bindings: [
                                .text(journal.id),
                                .int(journal.journalRevision),
                                .text(journal.state.rawValue),
                                .text(document),
                                .text(journal.updatedAt),
                            ]
                        )
                    } else {
                        try SQLiteHostRuntimeStateStatement.execute(
                            db,
                            sql: """
                            UPDATE update_bootstrap_journals
                            SET journal_revision = ?,
                                state = ?,
                                document_json = ?,
                                updated_at = ?
                            WHERE journal_id = ?
                            """,
                            bindings: [
                                .int(journal.journalRevision),
                                .text(journal.state.rawValue),
                                .text(document),
                                .text(journal.updatedAt),
                                .text(journal.id),
                            ]
                        )
                    }
                }
            }
        } catch let error as SQLiteUpdateBootstrapJournalRepositoryError {
            throw error
        } catch {
            throw SQLiteUpdateBootstrapJournalRepositoryError.writeFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    public func loadInstalledProductRelease(
    ) -> InstalledProductReleaseReadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                guard let release =
                    try SQLiteInstalledProductReleaseRecordReader.load(
                        db,
                        decoder: decoder,
                        validate: validateRelease
                    ) else {
                    return .missing
                }
                return .loaded(release)
            }
        } catch {
            return .failed(
                reason: "installed product release SQLite read failed path=\(databaseURL.path) reason=\(error)"
            )
        }
    }

    public func settlePackageInstallRelease(
        _ release: InstalledProductRelease
    ) throws {
        do {
            try validateRelease(release)
        } catch {
            throw SQLiteUpdateBootstrapJournalRepositoryError
                .invalidInstalledRelease(reason: String(describing: error))
        }
        guard release.source == .packageInstall else {
            throw SQLiteUpdateBootstrapJournalRepositoryError
                .invalidInstalledRelease(reason: "release source is not package-install")
        }

        do {
            try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                try connection.withImmediateTransaction(db) {
                    if let existing =
                        try SQLiteInstalledProductReleaseRecordReader.load(
                            db,
                            decoder: decoder,
                            validate: validateRelease
                        ) {
                        throw SQLiteUpdateBootstrapJournalRepositoryError
                            .installedReleaseAlreadyExists(
                                installationId: existing.installationId,
                                installationRevision:
                                    existing.installationRevision
                            )
                    }
                    try insertInstalledRelease(db, release: release)
                }
            }
        } catch let error as SQLiteUpdateBootstrapJournalRepositoryError {
            throw error
        } catch {
            throw SQLiteUpdateBootstrapJournalRepositoryError.writeFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    public func settleSucceededUpdate(
        journal: UpdateBootstrapJournal,
        release: InstalledProductRelease,
        expectedJournalRevision: Int,
        expectedInstallationRevision: Int
    ) throws {
        do {
            try validate(journal)
        } catch {
            throw SQLiteUpdateBootstrapJournalRepositoryError.invalidJournal(
                reason: String(describing: error)
            )
        }
        do {
            try validateRelease(release)
            try validateSettlement(release, journal)
        } catch {
            throw SQLiteUpdateBootstrapJournalRepositoryError
                .invalidInstalledRelease(reason: String(describing: error))
        }
        guard expectedInstallationRevision == journal.expectedInstallationRevision else {
            throw SQLiteUpdateBootstrapJournalRepositoryError
                .settlementInstallationRevisionMismatch(
                    journal: journal.expectedInstallationRevision,
                    caller: expectedInstallationRevision
                )
        }

        do {
            try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                try connection.withImmediateTransaction(db) {
                    try validateActiveOperationLease(db, journal: journal)
                    guard let current =
                        try SQLiteInstalledProductReleaseRecordReader.load(
                            db,
                            decoder: decoder,
                            validate: validateRelease
                        ) else {
                        throw SQLiteUpdateBootstrapJournalRepositoryError
                            .installedReleaseMissing
                    }
                    guard current.installationId
                        == release.installationId else {
                        throw SQLiteUpdateBootstrapJournalRepositoryError
                            .installedReleaseIdentityMismatch(
                                expected: release.installationId,
                                actual: current.installationId
                            )
                    }
                    guard current.installationRevision
                        == expectedInstallationRevision else {
                        throw SQLiteUpdateBootstrapJournalRepositoryError
                            .staleInstallationRevision(
                                expected: expectedInstallationRevision,
                                actual: current.installationRevision
                            )
                    }
                    guard release.installationRevision
                        == expectedInstallationRevision + 1 else {
                        throw SQLiteUpdateBootstrapJournalRepositoryError
                            .invalidNextRevision(
                                id: "installed-product-installation",
                                expected: expectedInstallationRevision + 1,
                                actual: release.installationRevision
                            )
                    }
                    guard release.releaseRevision
                        == current.releaseRevision + 1 else {
                        throw SQLiteUpdateBootstrapJournalRepositoryError
                            .invalidNextRevision(
                                id: "installed-product-release",
                                expected: current.releaseRevision + 1,
                                actual: release.releaseRevision
                            )
                    }
                    let existingRevision =
                        try SQLiteHostRuntimeStateStatement.scalarInt(
                            db,
                            sql: """
                            SELECT journal_revision
                            FROM update_bootstrap_journals
                            WHERE journal_id = ?
                            """,
                            bindings: [.text(journal.id)]
                        )
                    try validateRevision(
                        id: journal.id,
                        journalRevision: journal.journalRevision,
                        expectedRevision: expectedJournalRevision,
                        existingRevision: existingRevision
                    )
                    let journalDocument = String(
                        decoding: try encoder.encode(journal),
                        as: UTF8.self
                    )
                    try SQLiteHostRuntimeStateStatement.execute(
                        db,
                        sql: """
                        UPDATE update_bootstrap_journals
                        SET journal_revision = ?,
                            state = ?,
                            document_json = ?,
                            updated_at = ?
                        WHERE journal_id = ?
                        """,
                        bindings: [
                            .int(journal.journalRevision),
                            .text(journal.state.rawValue),
                            .text(journalDocument),
                            .text(journal.updatedAt),
                            .text(journal.id),
                        ]
                    )
                    try updateInstalledRelease(
                        db,
                        release: release,
                        expectedInstallationRevision:
                            expectedInstallationRevision,
                        expectedReleaseRevision: current.releaseRevision
                    )
                }
            }
        } catch let error as SQLiteUpdateBootstrapJournalRepositoryError {
            throw error
        } catch {
            throw SQLiteUpdateBootstrapJournalRepositoryError.writeFailed(
                path: databaseURL.path,
                reason: String(describing: error)
            )
        }
    }

    private func validateActiveOperationLease(
        _ db: OpaquePointer,
        journal: UpdateBootstrapJournal
    ) throws {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT state, operation_id, operation, target_installation_id,
                   expected_installation_revision
            FROM runtime_operation_lease
            WHERE singleton_id = 1
            """,
            columnCount: 5
        ) else {
            throw SQLiteUpdateBootstrapJournalRepositoryError.operationLeaseMissing
        }
        guard row[0] == "active" else {
            throw SQLiteUpdateBootstrapJournalRepositoryError
                .operationLeaseNotActive(state: row[0] ?? "NULL")
        }
        try requireLeaseField("operationId", expected: journal.operationId, actual: row[1])
        try requireLeaseField(
            "operation",
            expected: RuntimeOperation.applyUpdateBootstrap.rawValue,
            actual: row[2]
        )
        try requireLeaseField(
            "targetInstallationId",
            expected: journal.targetInstallationId,
            actual: row[3]
        )
        try requireLeaseField(
            "expectedInstallationRevision",
            expected: String(journal.expectedInstallationRevision),
            actual: row[4]
        )
    }

    private func requireLeaseField(
        _ field: String,
        expected: String,
        actual: String?
    ) throws {
        guard actual == expected else {
            throw SQLiteUpdateBootstrapJournalRepositoryError.operationLeaseMismatch(
                field: field,
                expected: expected,
                actual: actual ?? "NULL"
            )
        }
    }

    private func insertInstalledRelease(
        _ db: OpaquePointer,
        release: InstalledProductRelease
    ) throws {
        let document = String(
            decoding: try encoder.encode(release),
            as: UTF8.self
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            INSERT INTO installed_product_release(
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
                .text(release.installationId),
                .int(release.installationRevision),
                .int(release.releaseRevision),
                .text(release.source.rawValue),
                .text(document),
                .text(release.settledAt),
            ]
        )
    }

    private func updateInstalledRelease(
        _ db: OpaquePointer,
        release: InstalledProductRelease,
        expectedInstallationRevision: Int,
        expectedReleaseRevision: Int
    ) throws {
        let document = String(
            decoding: try encoder.encode(release),
            as: UTF8.self
        )
        try SQLiteHostRuntimeStateStatement.execute(
            db,
            sql: """
            UPDATE installed_product_release
            SET installation_revision = ?,
                release_revision = ?,
                source = ?,
                document_json = ?,
                settled_at = ?
            WHERE singleton_id = 1
              AND installation_id = ?
              AND installation_revision = ?
              AND release_revision = ?
            """,
            bindings: [
                .int(release.installationRevision),
                .int(release.releaseRevision),
                .text(release.source.rawValue),
                .text(document),
                .text(release.settledAt),
                .text(release.installationId),
                .int(expectedInstallationRevision),
                .int(expectedReleaseRevision),
            ]
        )
        let changed = try SQLiteHostRuntimeStateStatement.scalarInt(
            db,
            sql: "SELECT changes()"
        )
        guard changed == 1 else {
            throw SQLiteUpdateBootstrapJournalRepositoryError
                .installedReleaseCASFailed(
                    installationId: release.installationId,
                    expectedInstallationRevision:
                        expectedInstallationRevision,
                    expectedReleaseRevision: expectedReleaseRevision
                )
        }
    }

    private func read(
        sql: String,
        bindings: [SQLiteHostRuntimeStateBinding]
    ) -> UpdateBootstrapJournalReadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                guard let document = try SQLiteHostRuntimeStateStatement.scalarString(
                    db,
                    sql: sql,
                    bindings: bindings
                ) else {
                    return .missing
                }
                let journal = try decoder.decode(
                    UpdateBootstrapJournal.self,
                    from: Data(document.utf8)
                )
                try validate(journal)
                return .loaded(journal)
            }
        } catch {
            return .failed(
                reason: "update bootstrap journal SQLite read failed path=\(databaseURL.path) reason=\(error)"
            )
        }
    }

    private func validateRevision(
        id: String,
        journalRevision: Int,
        expectedRevision: Int?,
        existingRevision: Int?
    ) throws {
        switch (existingRevision, expectedRevision) {
        case (.none, .none):
            guard journalRevision == 1 else {
                throw SQLiteUpdateBootstrapJournalRepositoryError
                    .invalidNextRevision(
                        id: id,
                        expected: 1,
                        actual: journalRevision
                    )
            }
        case (.none, .some):
            throw SQLiteUpdateBootstrapJournalRepositoryError.missing(id: id)
        case (.some(let actual), .none):
            throw SQLiteUpdateBootstrapJournalRepositoryError.alreadyExists(
                id: id,
                revision: actual
            )
        case (.some(let actual), .some(let expected)):
            guard actual == expected else {
                throw SQLiteUpdateBootstrapJournalRepositoryError.staleRevision(
                    id: id,
                    expected: expected,
                    actual: actual
                )
            }
            guard journalRevision == expected + 1 else {
                throw SQLiteUpdateBootstrapJournalRepositoryError
                    .invalidNextRevision(
                        id: id,
                        expected: expected + 1,
                        actual: journalRevision
                    )
            }
        }
    }
}
