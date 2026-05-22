import Foundation
import RuntimeCore

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
            try replaceFile(preflight.backupRootfs, rootfsBase)
        case .rollbackRestoreRuntimeVersion:
            if fileExists(preflight.backupVersion) {
                try replaceFile(preflight.backupVersion, runtimeVersion)
            } else {
                try writeRuntimeVersion("rolled-back", preflight.backup)
            }
        case .rollbackRestoreUpdateArtifacts:
            try restoreBackupPathIfExists(
                preflight.backup.appendingPathComponent(UpdateBundleArtifactType.appBundle.rawValue),
                managerAppPath
            )
            try restoreBackupPathIfExists(
                preflight.backup.appendingPathComponent(UpdateBundleArtifactType.nginxBundle.rawValue),
                nginxDirectory
            )
            try restoreBackupPathIfExists(
                preflight.backup.appendingPathComponent(UpdateBundleArtifactType.guestDeploy.rawValue),
                deployDirectory
            )
            try restoreRuntimeToolsIfExists(
                preflight.backup.appendingPathComponent(UpdateBundleArtifactType.runtimeTools.rawValue)
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
