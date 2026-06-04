import Contracts
import Core
import Foundation

public struct RuntimeRollbackStepExecutor {
    public var stopRuntimeServices: () throws -> Void
    public var replaceFile: (URL, URL) throws -> Void
    public var fileExists: (URL) -> Bool
    public var writeRuntimeVersion: (String, URL) throws -> Void
    public var restoreBackupPathIfExists: (URL, URL) throws -> Void
    public var restoreRuntimeToolsIfExists: (URL) throws -> Void
    public var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    public var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void

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
                throw RuntimeWorkflowError.operationFailed("rollback rootfs restore requested without backup rootfs")
            }
            try replaceFile(backupRootfs, rootfsBase)
        case .rollbackRestoreRuntimeVersion:
            if fileExists(preflight.backupVersion) {
                try replaceFile(preflight.backupVersion, runtimeVersion)
            } else {
                try writeRuntimeVersion("rolled-back", preflight.backup)
            }
        case .rollbackRestoreUpdateArtifacts:
            for artifact in RuntimeRollbackManagedBackupArtifact.directoryArtifacts {
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
                preflight.backup.appendingPathComponent(UpdateBundleArtifactType.runtimeTools.rawValue)
            )
        case .rollbackStartRuntimeServices:
            try startRuntimeServices(preflight.restartPolicy)
        case .rollbackWaitRuntimeHealth:
            try waitForHealth(preflight.restartPolicy)
        default:
            throw RuntimeWorkflowError.operationFailed("unsupported command: rollback step \(step.rawValue)")
        }
    }
}

private enum RuntimeRollbackManagedBackupArtifact {
    case appBundle
    case nginxBundle
    case guestDeploy

    static let directoryArtifacts: [RuntimeRollbackManagedBackupArtifact] = [
        .appBundle,
        .nginxBundle,
        .guestDeploy,
    ]

    private var updateArtifactType: UpdateBundleArtifactType {
        switch self {
        case .appBundle:
            return .appBundle
        case .nginxBundle:
            return .nginxBundle
        case .guestDeploy:
            return .guestDeploy
        }
    }

    func backupPath(in backup: URL) -> URL {
        backup.appendingPathComponent(updateArtifactType.rawValue)
    }

    func restoreDestination(
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) -> URL {
        switch self {
        case .appBundle:
            return managerAppPath
        case .nginxBundle:
            return nginxDirectory
        case .guestDeploy:
            return deployDirectory
        }
    }
}
