import Foundation
import Core
import Contracts

struct RuntimeMigrationRunner {
    var isExecutableFile: (String) -> Bool
    var runRequired: (String, [String]) throws -> Void
    var log: (String) -> Void

    func run(_ migrations: [UpdateBundleMigration], stagedBundle: URL) throws {
        guard !migrations.isEmpty else {
            log("no migrations to run")
            return
        }

        let migrationDirectory = stagedBundle.appendingPathComponent("migrations")
        for migration in migrations {
            let migrationURL = migrationDirectory.appendingPathComponent(migration.name)
            guard isExecutableFile(migrationURL.path) else {
                throw LauncherError.bundleVerificationFailed(
                    "migration is not executable: \(migration.name)"
                )
            }
            log("running migration name=\(migration.name) path=\(migrationURL.path)")
            try runRequired(migrationURL.path, [])
        }
    }
}
