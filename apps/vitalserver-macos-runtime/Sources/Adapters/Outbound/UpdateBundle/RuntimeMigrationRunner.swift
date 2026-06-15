import Contracts
import Foundation
import Errors

public struct RuntimeMigrationRunner {
    public var executableState: (String) -> RuntimeFileState
    public var runRequired: (String, [String]) throws -> Void
    public var log: (String) -> Void

    public init(
        executableState: @escaping (String) -> RuntimeFileState,
        runRequired: @escaping (String, [String]) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.executableState = executableState
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
            try requireExecutableMigration(migrationURL)
            log("running migration name=\(migration.name) path=\(migrationURL.path)")
            try runRequired(migrationURL.path, [])
        }
    }

    private func requireExecutableMigration(_ url: URL) throws {
        switch executableState(url.path) {
        case .executable:
            return
        case .missing:
            throw RuntimeMigrationRunnerError.missingMigration(path: url.path)
        case .inspectFailed(let reason):
            throw RuntimeMigrationRunnerError.migrationInspectionFailed(path: url.path, reason: reason)
        case .present:
            throw RuntimeMigrationRunnerError.migrationNotExecutable(path: url.path, state: "present")
        case .unknown(let state):
            throw RuntimeMigrationRunnerError.migrationNotExecutable(path: url.path, state: state)
        }
    }
}
