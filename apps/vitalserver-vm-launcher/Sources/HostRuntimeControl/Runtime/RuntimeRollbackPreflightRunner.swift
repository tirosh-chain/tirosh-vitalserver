import Foundation
import RuntimeCore

struct RuntimeRollbackPreflightRunner {
    var requireLatestBackup: () throws -> URL
    var directoryExists: (URL) -> Bool
    var fileExists: (URL) -> Bool
    var serviceRestartPolicy: () -> RuntimeServiceRestartPolicy
    var log: (String) -> Void

    func prepare(requestedBackup: URL?) throws -> RollbackPreflightContext {
        let backup = try requestedBackup ?? requireLatestBackup()
        let backupRootfs = backup.appendingPathComponent(Constants.Artifacts.rootfsBase)
        let backupVersion = backup.appendingPathComponent(Constants.Artifacts.runtimeVersion)

        guard directoryExists(backup) else {
            throw LauncherError.missingFile(backup.path)
        }
        guard fileExists(backupRootfs) else {
            throw LauncherError.missingFile(backupRootfs.path)
        }

        let restartPolicy = serviceRestartPolicy()
        log(
            "rollback preflight backup=\(backup.path) vm=\(restartPolicy.restartVM ? "loaded" : "not-loaded") proxy=\(restartPolicy.restartProxy ? "loaded" : "not-loaded") watchdog=\(restartPolicy.restartWatchdog ? "loaded" : "not-loaded")"
        )

        return RollbackPreflightContext(
            backup: backup,
            backupRootfs: backupRootfs,
            backupVersion: backupVersion,
            restartPolicy: restartPolicy
        )
    }
}
