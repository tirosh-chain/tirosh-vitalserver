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
    public let backupDirectoryState: RuntimePathState

    public init(backup: URL, backupDirectoryState: RuntimePathState) {
        self.backup = backup
        self.backupDirectoryState = backupDirectoryState
    }
}

public enum RollbackRuntimeBackupRootfsObservationRequirement: Equatable, Sendable {
    case none
    case fileExists(URL)
}

public struct RollbackRuntimeBackupRootfsObservation: Equatable, Sendable {
    public let backupPlan: RollbackRuntimeBackupPlan
    public let backupRootfsState: RuntimePathState?

    public init(
        backupPlan: RollbackRuntimeBackupPlan,
        backupRootfsState: RuntimePathState?
    ) {
        self.backupPlan = backupPlan
        self.backupRootfsState = backupRootfsState
    }
}

public enum RollbackRuntimeBackupRootfsDecision: Equatable, Sendable {
    case proceed(RollbackRuntimeBackupPlan)
    case failed(message: String)
}

public enum RollbackRuntimeVersionRestoreDecision: Equatable, Sendable {
    case restoreBackupVersion(source: URL, destination: URL)
    case writeExplicitRollbackMarker(version: String, destinationDirectory: URL)
    case failed(message: String)
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
    public let backupVersionState: RuntimePathState?

    public init(
        requiredInput: RollbackRuntimeStepRequiredInput,
        backupVersionState: RuntimePathState?
    ) {
        self.requiredInput = requiredInput
        self.backupVersionState = backupVersionState
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
        backupDirectoryState: RuntimePathState
    ) -> RollbackRuntimeBackupDirectoryDecision {
        switch backupDirectoryState {
        case .directory:
            return .loadManifest(backup)
        case .missing:
            return .failed(message: missingFileFailureMessage(path: backup.path))
        case .inspectFailed(let reason):
            return .failed(message: "backup directory path inspection failed: \(backup.path) reason=\(reason)")
        case .file, .other, .unknown:
            return .failed(message: "backup directory path state is unexpected: \(backup.path) state=\(backupDirectoryState.rawValue)")
        }
    }

    public func rollbackBackupDirectoryDecision(
        observation: RollbackRuntimeBackupDirectoryObservation
    ) -> RollbackRuntimeBackupDirectoryDecision {
        rollbackBackupDirectoryDecision(
            backup: observation.backup,
            backupDirectoryState: observation.backupDirectoryState
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
        backupRootfsState: RuntimePathState?
    ) -> RollbackRuntimeBackupRootfsDecision {
        guard let backupRootfs = backupPlan.backupRootfs else {
            return .proceed(backupPlan)
        }
        switch backupRootfsState {
        case .file:
            return .proceed(backupPlan)
        case .missing:
            return .failed(message: missingFileFailureMessage(path: backupRootfs.path))
        case .inspectFailed(let reason):
            return .failed(message: "backup rootfs path inspection failed: \(backupRootfs.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed(message: "backup rootfs path state is unexpected: \(backupRootfs.path) state=\(backupRootfsState?.rawValue ?? "nil")")
        case nil:
            return .failed(message: "backup rootfs state is missing: \(backupRootfs.path)")
        }
    }

    public func rollbackBackupRootfsDecision(
        observation: RollbackRuntimeBackupRootfsObservation
    ) -> RollbackRuntimeBackupRootfsDecision {
        rollbackBackupRootfsDecision(
            backupPlan: observation.backupPlan,
            backupRootfsState: observation.backupRootfsState
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
        backupVersionState: RuntimePathState?,
        backup: URL
    ) -> RollbackRuntimeVersionRestoreDecision {
        switch backupVersionState {
        case .file:
            return .restoreBackupVersion(source: backupVersion, destination: runtimeVersion)
        case .missing:
            return .writeExplicitRollbackMarker(version: "rolled-back", destinationDirectory: backup)
        case .inspectFailed(let reason):
            return .failed(message: "backup runtime version path inspection failed: \(backupVersion.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed(message: "backup runtime version path state is unexpected: \(backupVersion.path) state=\(backupVersionState?.rawValue ?? "nil")")
        case nil:
            return .failed(message: "backup runtime version state is missing: \(backupVersion.path)")
        }
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
        backupVersionState: RuntimePathState?
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
                backupVersionState: backupVersionState,
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
            backupVersionState: observation.backupVersionState
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
