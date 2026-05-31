import Foundation
import Core
import Contracts

struct RuntimeRollbackStepExecutor {
    var stopRuntimeServices: () throws -> Void
    var replaceFile: (URL, URL) throws -> Void
    var fileExists: (URL) -> Bool
    var writeRuntimeVersion: (String, URL) throws -> Void
    var restoreBackupPathIfExists: (URL, URL) throws -> Void
    var restoreRuntimeToolsIfExists: (URL) throws -> Void
    var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void

    func execute(
        _ step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext,
        rootfsBase: URL,
        runtimeVersion: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) throws {
        switch step {
        case .rollbackStopRuntimeServices:
            try stopRuntimeServices()
        case .rollbackRestoreRootfsBase:
            guard let backupRootfs = preflight.backupRootfs else {
                throw LauncherError.unsupportedCommand("rollback rootfs restore requested without backup rootfs")
            }
            try replaceFile(backupRootfs, rootfsBase)
        case .rollbackRestoreRuntimeVersion:
            if fileExists(preflight.backupVersion) {
                try replaceFile(preflight.backupVersion, runtimeVersion)
            } else {
                try writeRuntimeVersion("rolled-back", preflight.backup)
            }
        case .rollbackRestoreUpdateArtifacts:
            for artifact in RuntimeManagedBackupArtifact.directoryArtifacts {
                try restoreBackupPathIfExists(
                    artifact.backupPath(in: preflight.backup),
                    artifact.restoreDestination(
                        managerAppPath: managerAppPath,
                        nginxDirectory: nginxDirectory,
                        deployDirectory: deployDirectory
                    )
                )
            }
            try restoreRuntimeToolsIfExists(
                RuntimeManagedBackupArtifact.runtimeTools.backupPath(in: preflight.backup)
            )
        case .rollbackStartRuntimeServices:
            try startRuntimeServices(preflight.restartPolicy)
        case .rollbackWaitRuntimeHealth:
            try waitForHealth(preflight.restartPolicy)
        default:
            throw LauncherError.unsupportedCommand("rollback step \(step.rawValue)")
        }
    }
}
