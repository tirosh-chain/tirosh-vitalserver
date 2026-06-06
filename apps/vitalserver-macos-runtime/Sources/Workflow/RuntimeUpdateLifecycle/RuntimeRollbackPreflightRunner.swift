import Contracts
import Domain
import Foundation

public struct RuntimeRollbackPreflightRunner {
    public var requireLatestBackup: () throws -> URL
    public var directoryExists: (URL) -> Bool
    public var fileExists: (URL) -> Bool
    public var loadManifest: (URL) throws -> BackupManifest
    public var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    public var log: (String) -> Void

    public init(
        requireLatestBackup: @escaping () throws -> URL,
        directoryExists: @escaping (URL) -> Bool,
        fileExists: @escaping (URL) -> Bool,
        loadManifest: @escaping (URL) throws -> BackupManifest,
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy,
        log: @escaping (String) -> Void
    ) {
        self.requireLatestBackup = requireLatestBackup
        self.directoryExists = directoryExists
        self.fileExists = fileExists
        self.loadManifest = loadManifest
        self.serviceRestartPolicy = serviceRestartPolicy
        self.log = log
    }

    public func prepare(_ command: RuntimeRollbackCommand) throws -> RollbackPreflightContext {
        let backup = try backupURL(for: command)
        let backupVersion = backup.appendingPathComponent(RuntimeFileNames.runtimeVersion)

        guard directoryExists(backup) else {
            throw RuntimeRollbackWorkflowError.operationFailed("missing file: \(backup.path)")
        }
        let manifest = try loadManifest(backup)
        let backupRootfs = manifest.rootfsBase.map { backup.appendingPathComponent($0) }
        if let backupRootfs, !fileExists(backupRootfs) {
            throw RuntimeRollbackWorkflowError.operationFailed("missing file: \(backupRootfs.path)")
        }

        let restartPolicy = serviceRestartPolicy()
        log(
            "rollback preflight backup=\(backup.path) vm=\(restartPolicy.restartVM ? "loaded" : "not-loaded") guestLogSync=\(restartPolicy.restartGuestLogSync ? "loaded" : "not-loaded") proxy=\(restartPolicy.restartProxy ? "loaded" : "not-loaded") watchdog=\(restartPolicy.restartWatchdog ? "loaded" : "not-loaded")"
        )

        return RollbackPreflightContext(
            backup: backup,
            backupRootfs: backupRootfs,
            backupVersion: backupVersion,
            restoresRootfsBase: backupRootfs != nil,
            restartPolicy: restartPolicy
        )
    }

    private func backupURL(for command: RuntimeRollbackCommand) throws -> URL {
        switch command {
        case .latestBackup:
            return try requireLatestBackup()
        case .specificBackup(let url):
            return url
        }
    }
}
