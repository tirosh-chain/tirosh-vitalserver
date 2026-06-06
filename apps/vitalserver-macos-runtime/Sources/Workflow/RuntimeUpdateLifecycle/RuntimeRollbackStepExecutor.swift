import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeRollbackStepExecutor {
    public var stopRuntimeServices: () throws -> Void
    public var replaceFile: (URL, URL) throws -> Void
    public var fileExists: (URL) -> Bool
    public var writeRuntimeVersion: (String, URL) throws -> Void
    public var restoreBackupPathIfExists: (URL, URL) throws -> Void
    public var restoreRuntimeToolsIfExists: (URL) throws -> Void
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    private var useCase: UpdateRuntimeUseCase {
        UpdateRuntimeUseCase()
    }

    public init(
        stopRuntimeServices: @escaping () throws -> Void,
        replaceFile: @escaping (URL, URL) throws -> Void,
        fileExists: @escaping (URL) -> Bool,
        writeRuntimeVersion: @escaping (String, URL) throws -> Void,
        restoreBackupPathIfExists: @escaping (URL, URL) throws -> Void,
        restoreRuntimeToolsIfExists: @escaping (URL) throws -> Void,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void,
        waitForHealth: @escaping (RuntimeServiceRestartPolicy) throws -> Void
    ) {
        self.stopRuntimeServices = stopRuntimeServices
        self.replaceFile = replaceFile
        self.fileExists = fileExists
        self.writeRuntimeVersion = writeRuntimeVersion
        self.restoreBackupPathIfExists = restoreBackupPathIfExists
        self.restoreRuntimeToolsIfExists = restoreRuntimeToolsIfExists
        self.startRuntimeServices = startRuntimeServices
        self.waitForHealth = waitForHealth
    }

    public func execute(
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
                throw RuntimeRollbackWorkflowError.operationFailed("rollback rootfs restore requested without backup rootfs")
            }
            try replaceFile(backupRootfs, rootfsBase)
        case .rollbackRestoreRuntimeVersion:
            let decision = useCase.rollbackVersionRestoreDecision(
                backupVersion: preflight.backupVersion,
                runtimeVersion: runtimeVersion,
                backupVersionExists: fileExists(preflight.backupVersion),
                backup: preflight.backup
            )
            switch decision {
            case .restoreBackupVersion(let source, let destination):
                try replaceFile(source, destination)
            case .writeExplicitRollbackMarker(let version, let destinationDirectory):
                try writeRuntimeVersion(version, destinationDirectory)
            }
        case .rollbackRestoreUpdateArtifacts:
            let restorePlan = useCase.rollbackManagedArtifactRestorePlan(
                backup: preflight.backup,
                managerAppPath: managerAppPath,
                nginxDirectory: nginxDirectory,
                deployDirectory: deployDirectory
            )
            for artifact in restorePlan.directoryRestores {
                try restoreBackupPathIfExists(
                    artifact.backupPath,
                    artifact.restoreDestination
                )
            }
            try restoreRuntimeToolsIfExists(
                restorePlan.runtimeToolsBackup
            )
        case .rollbackStartRuntimeServices:
            try startRuntimeServices(preflight.restartPolicy)
        case .rollbackWaitRuntimeHealth:
            try waitForHealth(preflight.restartPolicy)
        default:
            throw RuntimeRollbackWorkflowError.operationFailed(
                useCase.unsupportedRollbackStepFailureMessage(step: step)
            )
        }
    }
}
