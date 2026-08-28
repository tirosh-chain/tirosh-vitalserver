import Application
import Contracts
import Foundation

public struct SQLiteInstalledProductReleaseReader:
    InstalledProductReleaseReading,
    @unchecked Sendable
{
    public let databaseURL: URL
    private let connection: SQLiteHostRuntimeStateConnection
    private let decoder: JSONDecoder
    private let validate: (InstalledProductRelease) throws -> Void

    public init(
        databaseURL: URL,
        busyTimeoutMilliseconds: Int32 = 5_000,
        decoder: JSONDecoder = JSONDecoder(),
        validate: @escaping (InstalledProductRelease) throws -> Void
    ) {
        self.databaseURL = databaseURL
        self.connection = SQLiteHostRuntimeStateConnection(
            url: databaseURL,
            busyTimeoutMilliseconds: busyTimeoutMilliseconds
        )
        self.decoder = decoder
        self.validate = validate
    }

    public func loadInstalledProductRelease() -> InstalledProductReleaseReadResult {
        do {
            return try connection.withReadOnlyDatabase { db in
                _ = try SQLiteHostRuntimeStateSchema.validate(db)
                guard let release =
                    try SQLiteInstalledProductReleaseRecordReader.load(
                        db,
                        decoder: decoder,
                        validate: validate
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
}

enum SQLiteInstalledProductReleaseRecordReader {
    static func load(
        _ db: OpaquePointer,
        decoder: JSONDecoder,
        validate: (InstalledProductRelease) throws -> Void
    ) throws -> InstalledProductRelease? {
        guard let row = try SQLiteHostRuntimeStateStatement.stringRow(
            db,
            sql: """
            SELECT
              installation_id,
              installation_revision,
              release_revision,
              source,
              document_json,
              settled_at
            FROM installed_product_release
            WHERE singleton_id = 1
            """,
            columnCount: 6
        ) else {
            return nil
        }

        let installationID = try requiredText(
            row[0],
            field: "installation_id"
        )
        let installationRevision = try requiredInt(
            row[1],
            field: "installation_revision"
        )
        let releaseRevision = try requiredInt(
            row[2],
            field: "release_revision"
        )
        let source = try requiredText(row[3], field: "source")
        let document = try requiredText(row[4], field: "document_json")
        let settledAt = try requiredText(row[5], field: "settled_at")
        let release = try decoder.decode(
            InstalledProductRelease.self,
            from: Data(document.utf8)
        )
        try validate(release)
        try requireEqual(
            release.installationId,
            installationID,
            field: "installation_id"
        )
        try requireEqual(
            release.installationRevision,
            installationRevision,
            field: "installation_revision"
        )
        try requireEqual(
            release.releaseRevision,
            releaseRevision,
            field: "release_revision"
        )
        try requireEqual(
            release.source.rawValue,
            source,
            field: "source"
        )
        try requireEqual(
            release.settledAt,
            settledAt,
            field: "settled_at"
        )
        return release
    }

    private static func requiredText(
        _ value: String?,
        field: String
    ) throws -> String {
        guard let value, !value.isEmpty else {
            throw invalid(field: field, value: value ?? "NULL")
        }
        return value
    }

    private static func requiredInt(
        _ value: String?,
        field: String
    ) throws -> Int {
        guard let value, let parsed = Int(value) else {
            throw invalid(field: field, value: value ?? "NULL")
        }
        return parsed
    }

    private static func requireEqual<T: Equatable>(
        _ documentValue: T,
        _ rowValue: T,
        field: String
    ) throws {
        guard documentValue == rowValue else {
            throw invalid(
                field: field,
                value: "row=\(rowValue) document=\(documentValue)"
            )
        }
    }

    private static func invalid(
        field: String,
        value: String
    ) -> SQLiteHostRuntimeStateDatabaseError {
        .metadataInvalid(
            field: "installed_product_release.\(field)",
            value: value
        )
    }
}
