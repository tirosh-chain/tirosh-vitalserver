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
                guard let document = try SQLiteHostRuntimeStateStatement.scalarString(
                    db,
                    sql: """
                    SELECT document_json
                    FROM installed_product_release
                    WHERE singleton_id = 1
                    """
                ) else {
                    return .missing
                }
                let release = try decoder.decode(
                    InstalledProductRelease.self,
                    from: Data(document.utf8)
                )
                try validate(release)
                return .loaded(release)
            }
        } catch {
            return .failed(
                reason: "installed product release SQLite read failed path=\(databaseURL.path) reason=\(error)"
            )
        }
    }
}
