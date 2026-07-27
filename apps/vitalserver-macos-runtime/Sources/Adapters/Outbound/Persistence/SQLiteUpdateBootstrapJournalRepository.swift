import Application
import Contracts
import Domain
import Foundation

public enum SQLiteUpdateBootstrapJournalRepositoryError:
    Error,
    Equatable,
    Sendable
{
    case invalidJournal(UpdateBootstrapJournalValidationError)
    case missing(id: String)
    case alreadyExists(id: String, revision: Int)
    case staleRevision(id: String, expected: Int, actual: Int)
    case invalidNextRevision(id: String, expected: Int, actual: Int)
    case writeFailed(path: String, reason: String)
}

public struct SQLiteUpdateBootstrapJournalRepository:
    UpdateBootstrapJournalRepository,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.encoder = encoder
        self.decoder = decoder
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
            try UpdateBootstrapJournalPolicy.validate(journal)
        } catch let error as UpdateBootstrapJournalValidationError {
            throw SQLiteUpdateBootstrapJournalRepositoryError.invalidJournal(error)
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
                try UpdateBootstrapJournalPolicy.validate(journal)
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
