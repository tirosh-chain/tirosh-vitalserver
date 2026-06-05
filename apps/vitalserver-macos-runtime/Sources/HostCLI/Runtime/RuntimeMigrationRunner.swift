import Contracts
import Foundation
import RuntimeWorkflow

public struct RuntimeMigrationRunner {
    public var isExecutableFile: (String) -> Bool
    public var runRequired: (String, [String]) throws -> Void
    public var log: (String) -> Void

    public init(
        isExecutableFile: @escaping (String) -> Bool,
        runRequired: @escaping (String, [String]) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.isExecutableFile = isExecutableFile
        self.runRequired = runRequired
        self.log = log
    }

    public func run(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        guard !migrations.isEmpty else {
            log("no migrations to run")
            return
        }

        let migrationDirectory = stagedBundle.appendingPathComponent("migrations")
        for migration in migrations {
            let migrationURL = migrationDirectory.appendingPathComponent(migration.name)
            guard isExecutableFile(migrationURL.path) else {
                throw RuntimeWorkflowError.operationFailed(
                    "bundle verification failed: migration is not executable: \(migration.name)"
                )
            }
            log("running migration name=\(migration.name) path=\(migrationURL.path)")
            try runRequired(migrationURL.path, [])
        }
    }
}
