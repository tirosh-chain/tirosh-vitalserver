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
    case missing(id: String)
    case alreadyExists(id: String, revision: Int)
    case staleRevision(id: String, expected: Int, actual: Int)
    case invalidNextRevision(id: String, expected: Int, actual: Int)
    case writeFailed(path: String, reason: String)
}

public struct SQLiteUpdateBootstrapJournalRepository:
    UpdateBootstrapJournalRepository,
    InstalledUpdateReleaseReading,
    SucceededUpdateSettlementWriting,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let validate: (UpdateBootstrapJournal) throws -> Void
    private let validateRelease: (InstalledUpdateRelease) throws -> Void
    private let validateSettlement: (
        InstalledUpdateRelease,
        UpdateBootstrapJournal
    ) throws -> Void

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        validate: @escaping (UpdateBootstrapJournal) throws -> Void,
        validateRelease: @escaping (InstalledUpdateRelease) throws -> Void,
        validateSettlement: @escaping (
            InstalledUpdateRelease,
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

    public func loadInstalledUpdateRelease(
    ) -> InstalledUpdateReleaseReadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                guard let document =
                    try SQLiteHostRuntimeStateStatement.scalarString(
                        db,
                        sql: """
                        SELECT document_json
                        FROM installed_update_release
                        WHERE singleton_id = 1
                        """
                    )
                else {
                    return .missing
                }
                let release = try decoder.decode(
                    InstalledUpdateRelease.self,
                    from: Data(document.utf8)
                )
                try validateRelease(release)
                return .loaded(release)
            }
        } catch {
            return .failed(
                reason: "installed update release SQLite read failed path=\(databaseURL.path) reason=\(error)"
            )
        }
    }

    public func settleSucceededUpdate(
        journal: UpdateBootstrapJournal,
        release: InstalledUpdateRelease,
        expectedJournalRevision: Int
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

        do {
            try connection.withWritableDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                try connection.withImmediateTransaction(db) {
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
                    let releaseDocument = String(
                        decoding: try encoder.encode(release),
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
                    try SQLiteHostRuntimeStateStatement.execute(
                        db,
                        sql: """
                        INSERT INTO installed_update_release(
                          singleton_id,
                          update_id,
                          journal_id,
                          journal_revision,
                          document_json,
                          settled_at
                        ) VALUES (1, ?, ?, ?, ?, ?)
                        ON CONFLICT(singleton_id) DO UPDATE SET
                          update_id = excluded.update_id,
                          journal_id = excluded.journal_id,
                          journal_revision = excluded.journal_revision,
                          document_json = excluded.document_json,
                          settled_at = excluded.settled_at
                        """,
                        bindings: [
                            .text(release.updateId),
                            .text(release.journalId),
                            .int(release.journalRevision),
                            .text(releaseDocument),
                            .text(release.settledAt),
                        ]
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
