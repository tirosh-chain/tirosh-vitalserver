import Contracts
import Domain
import Foundation

public struct RollbackRuntimePlan: Equatable, Sendable {
    public let operationPlan: RuntimeOperationPlan

    public init(operationPlan: RuntimeOperationPlan) {
        self.operationPlan = operationPlan
    }
}

public struct RollbackRuntimePreflightPlan: Equatable, Sendable {
    public let serviceRestartLogMessage: String

    public init(serviceRestartLogMessage: String) {
        self.serviceRestartLogMessage = serviceRestartLogMessage
    }
}

public struct RollbackRuntimeBackupPlan: Equatable, Sendable {
    public let backup: URL
    public let backupRootfs: URL?
    public let backupVersion: URL
    public let restoresRootfsBase: Bool

    public init(
        backup: URL,
        backupRootfs: URL?,
        backupVersion: URL,
        restoresRootfsBase: Bool
    ) {
        self.backup = backup
        self.backupRootfs = backupRootfs
        self.backupVersion = backupVersion
        self.restoresRootfsBase = restoresRootfsBase
    }
}

public enum RollbackRuntimeBackupSelection: Equatable, Sendable {
    case latestBackup
    case specificBackup(URL)
}

public enum RollbackRuntimeBackupDirectoryDecision: Equatable, Sendable {
    case loadManifest(URL)
    case failed(message: String)
}

public struct RollbackRuntimeBackupDirectoryObservation: Equatable, Sendable {
    public let backup: URL
    public let directoryExists: Bool

    public init(backup: URL, directoryExists: Bool) {
        self.backup = backup
        self.directoryExists = directoryExists
    }
}

public enum RollbackRuntimeBackupRootfsObservationRequirement: Equatable, Sendable {
    case none
    case fileExists(URL)
}

public struct RollbackRuntimeBackupRootfsObservation: Equatable, Sendable {
    public let backupPlan: RollbackRuntimeBackupPlan
    public let backupRootfsExists: Bool?

    public init(
        backupPlan: RollbackRuntimeBackupPlan,
        backupRootfsExists: Bool?
    ) {
        self.backupPlan = backupPlan
        self.backupRootfsExists = backupRootfsExists
    }
}

public enum RollbackRuntimeBackupRootfsDecision: Equatable, Sendable {
    case proceed(RollbackRuntimeBackupPlan)
    case failed(message: String)
}

public enum RollbackRuntimeVersionRestoreDecision: Equatable, Sendable {
    case restoreBackupVersion(source: URL, destination: URL)
    case writeExplicitRollbackMarker(version: String, destinationDirectory: URL)
}

public struct RollbackRuntimeManagedArtifactRestore: Equatable, Sendable {
    public let backupPath: URL
    public let restoreDestination: URL

    public init(backupPath: URL, restoreDestination: URL) {
        self.backupPath = backupPath
        self.restoreDestination = restoreDestination
    }
}

public struct RollbackRuntimeManagedArtifactRestorePlan: Equatable, Sendable {
    public let directoryRestores: [RollbackRuntimeManagedArtifactRestore]
    public let runtimeToolsBackup: URL

    public init(
        directoryRestores: [RollbackRuntimeManagedArtifactRestore],
        runtimeToolsBackup: URL
    ) {
        self.directoryRestores = directoryRestores
        self.runtimeToolsBackup = runtimeToolsBackup
    }
}

public enum RollbackRuntimeStepExecutionPlan: Equatable, Sendable {
    case stopRuntimeServices
    case restoreRootfsBase(source: URL, destination: URL)
    case restoreRuntimeVersion(RollbackRuntimeVersionRestoreDecision)
    case restoreUpdateArtifacts(RollbackRuntimeManagedArtifactRestorePlan)
    case startRuntimeServices(RuntimeServiceRestartPolicy)
    case waitRuntimeHealth(RuntimeServiceRestartPolicy)
    case failed(failureMessage: String)
    case unsupported(failureMessage: String)
}

public enum RollbackRuntimeStepRequiredInput: Equatable, Sendable {
    case none
    case backupVersionExists(URL)
}

public struct RollbackRuntimeStepRequiredInputObservation: Equatable, Sendable {
    public let requiredInput: RollbackRuntimeStepRequiredInput
    public let backupVersionExists: Bool

    public init(
        requiredInput: RollbackRuntimeStepRequiredInput,
        backupVersionExists: Bool
    ) {
        self.requiredInput = requiredInput
        self.backupVersionExists = backupVersionExists
    }
}

public struct RollbackRuntimeCompletionPlan: Equatable, Sendable {
    public let statusPlan: UpdateRuntimeStatusPlan
    public let restoredBackupLogMessage: String
    public let preservedVMDiskLogMessage: String

    public init(
        statusPlan: UpdateRuntimeStatusPlan,
        restoredBackupLogMessage: String,
        preservedVMDiskLogMessage: String
    ) {
        self.statusPlan = statusPlan
        self.restoredBackupLogMessage = restoredBackupLogMessage
        self.preservedVMDiskLogMessage = preservedVMDiskLogMessage
    }
}

public struct RollbackRuntimeUseCase {
    public init() {}

    public func planRollback(for preflight: RollbackPreflightContext) -> RollbackRuntimePlan {
        RollbackRuntimePlan(
            operationPlan: RuntimeOperationPlans.rollback(restoresRootfsBase: preflight.restoresRootfsBase)
        )
    }

    public func rollbackStartedPlan(backupPath: String) -> UpdateRuntimeLoggedStatusPlan {
        UpdateRuntimeLoggedStatusPlan(
            logMessage: "rollback started backup=\(backupPath)",
            status: .recovering,
            operation: .rollback,
            statusMessage: "rollback started"
        )
    }

    public func rollbackProgressLogMessage(event: RuntimeStepExecutionEvent) -> String {
        "step=\(event.step.rawValue) status=\(event.stepStatus.rawValue)"
    }

    public func rollbackCompletedPlan(
        backupPath: String,
        vmDiskPath: String
    ) -> RollbackRuntimeCompletionPlan {
        RollbackRuntimeCompletionPlan(
            statusPlan: UpdateRuntimeStatusPlan(
                status: .healthy,
                operation: .rollback,
                message: "rollback completed"
            ),
            restoredBackupLogMessage: "rollback restored backup=\(backupPath)",
            preservedVMDiskLogMessage: "mutable VM disk preserved path=\(vmDiskPath)"
        )
    }

    public func rollbackPreflightPlan(
        backup: URL,
        restartPolicy: RuntimeServiceRestartPolicy
    ) -> RollbackRuntimePreflightPlan {
        RollbackRuntimePreflightPlan(
            serviceRestartLogMessage: "rollback preflight backup=\(backup.path) vm=\(loadedText(restartPolicy.restartVM)) guestLogSync=\(loadedText(restartPolicy.restartGuestLogSync)) proxy=\(loadedText(restartPolicy.restartProxy)) watchdog=\(loadedText(restartPolicy.restartWatchdog))"
        )
    }

    public func rollbackBackupPlan(
        backup: URL,
        manifest: BackupManifest
    ) -> RollbackRuntimeBackupPlan {
        let backupRootfs = manifest.rootfsBase.map { backup.appendingPathComponent($0) }
        return RollbackRuntimeBackupPlan(
            backup: backup,
            backupRootfs: backupRootfs,
            backupVersion: backup.appendingPathComponent(RuntimeFileNames.runtimeVersion),
            restoresRootfsBase: backupRootfs != nil
        )
    }

    public func rollbackBackupDirectoryDecision(
        backup: URL,
        directoryExists: Bool
    ) -> RollbackRuntimeBackupDirectoryDecision {
        guard directoryExists else {
            return .failed(message: missingFileFailureMessage(path: backup.path))
        }
        return .loadManifest(backup)
    }

    public func rollbackBackupDirectoryDecision(
        observation: RollbackRuntimeBackupDirectoryObservation
    ) -> RollbackRuntimeBackupDirectoryDecision {
        rollbackBackupDirectoryDecision(
            backup: observation.backup,
            directoryExists: observation.directoryExists
        )
    }

    public func rollbackBackupRootfsObservationRequirement(
        backupPlan: RollbackRuntimeBackupPlan
    ) -> RollbackRuntimeBackupRootfsObservationRequirement {
        guard let backupRootfs = backupPlan.backupRootfs else {
            return .none
        }
        return .fileExists(backupRootfs)
    }

    public func rollbackBackupRootfsDecision(
        backupPlan: RollbackRuntimeBackupPlan,
        backupRootfsExists: Bool?
    ) -> RollbackRuntimeBackupRootfsDecision {
        guard let backupRootfs = backupPlan.backupRootfs else {
            return .proceed(backupPlan)
        }
        guard backupRootfsExists == true else {
            return .failed(message: missingFileFailureMessage(path: backupRootfs.path))
        }
        return .proceed(backupPlan)
    }

    public func rollbackBackupRootfsDecision(
        observation: RollbackRuntimeBackupRootfsObservation
    ) -> RollbackRuntimeBackupRootfsDecision {
        rollbackBackupRootfsDecision(
            backupPlan: observation.backupPlan,
            backupRootfsExists: observation.backupRootfsExists
        )
    }

    public func rollbackBackupSelection(command: RuntimeRollbackCommand) -> RollbackRuntimeBackupSelection {
        switch command {
        case .latestBackup:
            return .latestBackup
        case .specificBackup(let url):
            return .specificBackup(url)
        }
    }

    public func rollbackVersionRestoreDecision(
        backupVersion: URL,
        runtimeVersion: URL,
        backupVersionExists: Bool,
        backup: URL
    ) -> RollbackRuntimeVersionRestoreDecision {
        if backupVersionExists {
            return .restoreBackupVersion(source: backupVersion, destination: runtimeVersion)
        }
        return .writeExplicitRollbackMarker(version: "rolled-back", destinationDirectory: backup)
    }

    public func rollbackManagedArtifactRestorePlan(
        backup: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL
    ) -> RollbackRuntimeManagedArtifactRestorePlan {
        RollbackRuntimeManagedArtifactRestorePlan(
            directoryRestores: [
                RollbackRuntimeManagedArtifactRestore(
                    backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.appBundle.rawValue),
                    restoreDestination: managerAppPath
                ),
                RollbackRuntimeManagedArtifactRestore(
                    backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.nginxBundle.rawValue),
                    restoreDestination: nginxDirectory
                ),
                RollbackRuntimeManagedArtifactRestore(
                    backupPath: backup.appendingPathComponent(UpdateBundleArtifactType.guestDeploy.rawValue),
                    restoreDestination: deployDirectory
                ),
            ],
            runtimeToolsBackup: backup.appendingPathComponent(UpdateBundleArtifactType.runtimeTools.rawValue)
        )
    }

    public func rollbackStepExecutionPlan(
        step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext,
        rootfsBase: URL,
        runtimeVersion: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL,
        backupVersionExists: Bool
    ) -> RollbackRuntimeStepExecutionPlan {
        switch step {
        case .rollbackStopRuntimeServices:
            return .stopRuntimeServices
        case .rollbackRestoreRootfsBase:
            guard let backupRootfs = preflight.backupRootfs else {
                return .failed(failureMessage: rollbackRootfsRestoreMissingBackupRootfsFailureMessage())
            }
            return .restoreRootfsBase(source: backupRootfs, destination: rootfsBase)
        case .rollbackRestoreRuntimeVersion:
            return .restoreRuntimeVersion(rollbackVersionRestoreDecision(
                backupVersion: preflight.backupVersion,
                runtimeVersion: runtimeVersion,
                backupVersionExists: backupVersionExists,
                backup: preflight.backup
            ))
        case .rollbackRestoreUpdateArtifacts:
            return .restoreUpdateArtifacts(rollbackManagedArtifactRestorePlan(
                backup: preflight.backup,
                managerAppPath: managerAppPath,
                nginxDirectory: nginxDirectory,
                deployDirectory: deployDirectory
            ))
        case .rollbackStartRuntimeServices:
            return .startRuntimeServices(preflight.restartPolicy)
        case .rollbackWaitRuntimeHealth:
            return .waitRuntimeHealth(preflight.restartPolicy)
        default:
            return .unsupported(failureMessage: unsupportedRollbackStepFailureMessage(step: step))
        }
    }

    public func rollbackStepExecutionPlan(
        step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext,
        rootfsBase: URL,
        runtimeVersion: URL,
        managerAppPath: URL,
        nginxDirectory: URL,
        deployDirectory: URL,
        observation: RollbackRuntimeStepRequiredInputObservation
    ) -> RollbackRuntimeStepExecutionPlan {
        guard observation.requiredInput == rollbackStepRequiredInput(step: step, preflight: preflight) else {
            return .failed(failureMessage: "rollback step required input observation does not match required input")
        }
        return rollbackStepExecutionPlan(
            step: step,
            preflight: preflight,
            rootfsBase: rootfsBase,
            runtimeVersion: runtimeVersion,
            managerAppPath: managerAppPath,
            nginxDirectory: nginxDirectory,
            deployDirectory: deployDirectory,
            backupVersionExists: observation.backupVersionExists
        )
    }

    public func rollbackStepRequiredInput(
        step: RuntimeWorkflowStep,
        preflight: RollbackPreflightContext
    ) -> RollbackRuntimeStepRequiredInput {
        switch step {
        case .rollbackRestoreRuntimeVersion:
            return .backupVersionExists(preflight.backupVersion)
        default:
            return .none
        }
    }

    public func unsupportedRollbackStepFailureMessage(step: RuntimeWorkflowStep) -> String {
        "unsupported command: rollback step \(step.rawValue)"
    }

    public func rollbackRootfsRestoreMissingBackupRootfsFailureMessage() -> String {
        "rollback rootfs restore requested without backup rootfs"
    }

    private func missingFileFailureMessage(path: String) -> String {
        "missing file: \(path)"
    }

    private func loadedText(_ loaded: Bool) -> String {
        loaded ? "loaded" : "not-loaded"
    }
}
