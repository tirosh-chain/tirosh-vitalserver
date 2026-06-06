import Contracts
import Domain
import Foundation
import Errors

public struct ApplyRuntimeBundleInitialHealthDecision: Equatable, Sendable {
    public let shouldWarn: Bool
    public let warningMessage: String?

    public init(shouldWarn: Bool, warningMessage: String?) {
        self.shouldWarn = shouldWarn
        self.warningMessage = warningMessage
    }
}

public enum ApplyRuntimeBundleInitialHealthWarningPlan: Equatable, Sendable {
    case continueWithoutWarning
    case continueWithWarning(String)
}

public struct ApplyRuntimeBundlePlan: Equatable, Sendable {
    public let operationPlan: RuntimeOperationPlan

    public init(operationPlan: RuntimeOperationPlan) {
        self.operationPlan = operationPlan
    }
}

public struct ApplyRuntimeBundleFailureRecoveryPlan: Equatable, Sendable {
    public let backup: URL
    public let restartPolicy: RuntimeServiceRestartPolicy
    public let rollbackStartedPlan: UpdateRuntimeLoggedStatusPlan
    public let rollbackCompletedPlan: UpdateRuntimeStatusPlan

    public init(
        backup: URL,
        restartPolicy: RuntimeServiceRestartPolicy,
        rollbackStartedPlan: UpdateRuntimeLoggedStatusPlan,
        rollbackCompletedPlan: UpdateRuntimeStatusPlan
    ) {
        self.backup = backup
        self.restartPolicy = restartPolicy
        self.rollbackStartedPlan = rollbackStartedPlan
        self.rollbackCompletedPlan = rollbackCompletedPlan
    }
}

public enum RuntimeBundleMaterializationCleanupPlan: Equatable, Sendable {
    case none
    case cleanupTemporaryRoot(URL)
}

public struct ApplyRuntimeBundlePreflightCapabilityPlan: Equatable, Sendable {
    public let instructions: [ApplyRuntimeBundlePreflightCapabilityInstruction]
    public let serviceRestartLogMessage: String

    public init(
        instructions: [ApplyRuntimeBundlePreflightCapabilityInstruction],
        serviceRestartLogMessage: String
    ) {
        self.instructions = instructions
        self.serviceRestartLogMessage = serviceRestartLogMessage
    }
}

public enum ApplyRuntimeBundlePreflightCapabilityInstruction: Equatable, Sendable {
    case requireRuntimeDiskHealthAllowsUpdate
    case requireGuestCapability(RuntimeGuestCapabilityRequirement)
}

public struct ApplyRuntimeBundlePreflightManifestPlan: Equatable, Sendable {
    public let stagedRootfs: URL?
    public let manifestLogMessage: String
    public let backupReason: String
    public let backupStartedLogMessage: String

    public init(
        stagedRootfs: URL?,
        manifestLogMessage: String,
        backupReason: String,
        backupStartedLogMessage: String
    ) {
        self.stagedRootfs = stagedRootfs
        self.manifestLogMessage = manifestLogMessage
        self.backupReason = backupReason
        self.backupStartedLogMessage = backupStartedLogMessage
    }
}

public enum ApplyRuntimeBundleDiskHealthDecision: Equatable, Sendable {
    case allowed
    case blocked(blockers: [RuntimeVMError], logMessage: String, failureMessage: String)
}

public struct ApplyRuntimeBundleRootfsStoragePreflightPlan: Equatable, Sendable {
    public let rootfsStorage: RuntimeUpdateRootfsStorageInput
    public let logMessage: String

    public init(rootfsStorage: RuntimeUpdateRootfsStorageInput, logMessage: String) {
        self.rootfsStorage = rootfsStorage
        self.logMessage = logMessage
    }
}

public enum ApplyRuntimeBundleStopExecutionPlan: Equatable, Sendable {
    case stopServicesDirectly
    case prepareGuestShutdownAndStopServicesAfterPoweroff(manifest: UpdateBundleManifest)
}

public enum ApplyRuntimeBundleRootfsReplacementPlan: Equatable, Sendable {
    case skip(logMessage: String)
    case replace(stagedRootfs: URL, rootfsBase: URL)
}

public struct ApplyRuntimeBundleRootfsReplacementExecutionPlan: Equatable, Sendable {
    public let startedLogMessage: String
    public let completedLogMessage: String

    public init(startedLogMessage: String, completedLogMessage: String) {
        self.startedLogMessage = startedLogMessage
        self.completedLogMessage = completedLogMessage
    }
}

public struct ApplyRuntimeBundleRootfsReplacementObservation: Equatable, Sendable {
    public let stagedRootfs: URL
    public let rootfsBase: URL
    public let stagedRootfsBytes: UInt64

    public init(
        stagedRootfs: URL,
        rootfsBase: URL,
        stagedRootfsBytes: UInt64
    ) {
        self.stagedRootfs = stagedRootfs
        self.rootfsBase = rootfsBase
        self.stagedRootfsBytes = stagedRootfsBytes
    }
}

public enum ApplyRuntimeBundleRootfsStorageObservationPlan: Equatable, Sendable {
    case unchanged(ApplyRuntimeBundleRootfsStoragePreflightPlan)
    case replacing(stagedRootfs: URL, rootfsBase: URL)
}

public struct ApplyRuntimeBundleRootfsStorageObservation: Equatable, Sendable {
    public let stagedRootfs: URL
    public let stagedRootfsExists: Bool
    public let installedRootfsBytes: UInt64?
    public let incomingRootfsBytes: UInt64?

    public init(
        stagedRootfs: URL,
        stagedRootfsExists: Bool,
        installedRootfsBytes: UInt64?,
        incomingRootfsBytes: UInt64?
    ) {
        self.stagedRootfs = stagedRootfs
        self.stagedRootfsExists = stagedRootfsExists
        self.installedRootfsBytes = installedRootfsBytes
        self.incomingRootfsBytes = incomingRootfsBytes
    }
}

public enum ApplyRuntimeBundleRootfsStorageDecision: Equatable, Sendable {
    case planned(ApplyRuntimeBundleRootfsStoragePreflightPlan)
    case failed(message: String)
}

public enum ApplyRuntimeBundleStepExecutionPlan: Equatable, Sendable {
    case stopRuntimeServices(ApplyRuntimeBundleStopExecutionPlan)
    case replaceRootfsBase(ApplyRuntimeBundleRootfsReplacementPlan)
    case replaceUpdateArtifacts(artifacts: [UpdateBundleArtifact], stagedBundle: URL)
    case runMigrations(migrations: [UpdateBundleMigration], stagedBundle: URL)
    case refreshCloudInitSeed(manifest: UpdateBundleManifest)
    case writeRuntimeVersion(version: String, stagedBundle: URL)
    case startRuntimeServices(RuntimeServiceRestartPolicy)
    case activateGuestUpdate(manifest: UpdateBundleManifest)
    case waitRuntimeHealth(RuntimeServiceRestartPolicy)
    case unsupported(failureMessage: String)
}

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

public struct UpdateRuntimeStatusPlan: Equatable, Sendable {
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let message: String

    public init(
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String
    ) {
        self.status = status
        self.operation = operation
        self.message = message
    }
}

public struct UpdateRuntimeLoggedStatusPlan: Equatable, Sendable {
    public let logMessage: String
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let statusMessage: String

    public init(
        logMessage: String,
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        statusMessage: String
    ) {
        self.logMessage = logMessage
        self.status = status
        self.operation = operation
        self.statusMessage = statusMessage
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

public struct RuntimeGuestActivationPlan: Equatable, Sendable {
    public let requiresActivation: Bool
    public let version: String
    public let skippedLogMessage: String?
    public let requestedLogMessage: String?
    public let completedLogMessage: String?

    public init(
        requiresActivation: Bool,
        version: String,
        skippedLogMessage: String?,
        requestedLogMessage: String?,
        completedLogMessage: String?
    ) {
        self.requiresActivation = requiresActivation
        self.version = version
        self.skippedLogMessage = skippedLogMessage
        self.requestedLogMessage = requestedLogMessage
        self.completedLogMessage = completedLogMessage
    }
}

public enum RuntimeGuestActivationExecutionPlan: Equatable, Sendable {
    case skip(logMessage: String)
    case activate(version: String, requestedLogMessage: String, completedLogMessage: String)
}

public enum RuntimeGuestActivationVMStartPlan: Equatable, Sendable {
    case alreadyLoaded
    case startService
}

public struct RuntimeGuestShutdownPlan: Equatable, Sendable {
    public let version: String
    public let requestedLogMessage: String
    public let readyLogMessage: String

    public init(
        version: String,
        requestedLogMessage: String,
        readyLogMessage: String
    ) {
        self.version = version
        self.requestedLogMessage = requestedLogMessage
        self.readyLogMessage = readyLogMessage
    }
}

public enum RuntimeGuestShutdownExecutionPlan: Equatable, Sendable {
    case prepare(version: String, requestLog: String, readyLog: String)
}

public struct RuntimeGuestWaitResultPlan: Equatable, Sendable {
    public let logMessage: String?
    public let failureMessage: String?

    public init(logMessage: String?, failureMessage: String?) {
        self.logMessage = logMessage
        self.failureMessage = failureMessage
    }
}

public enum RuntimeGuestWaitResultExecutionPlan: Equatable, Sendable {
    case completed(logMessage: String)
    case failed(logMessage: String, failureMessage: String)
    case failedWithoutLog(failureMessage: String)
}

public struct RuntimeGuestCapabilityDecision: Equatable, Sendable {
    public let isSupported: Bool
    public let failure: RuntimeGuestCapabilityCheckError?

    public init(isSupported: Bool, failure: RuntimeGuestCapabilityCheckError?) {
        self.isSupported = isSupported
        self.failure = failure
    }
}

public enum RuntimeGuestCapabilityRequirementPlan: Equatable, Sendable {
    case supported
    case failed(RuntimeGuestCapabilityCheckError)
}

public struct UpdateRuntimeUseCase {
    public init() {}

    public func initialHealthDecision(
        snapshot: RuntimeHealthSnapshot
    ) -> ApplyRuntimeBundleInitialHealthDecision {
        guard !RuntimeHealthSnapshotPolicy.isHealthy(snapshot) else {
            return ApplyRuntimeBundleInitialHealthDecision(
                shouldWarn: false,
                warningMessage: nil
            )
        }
        let reasonText = RuntimeFailureReasonText.describe(snapshot.failureReasons)
        return ApplyRuntimeBundleInitialHealthDecision(
            shouldWarn: true,
            warningMessage: "bundle apply preflight warning runtime unhealthy reasons=\(reasonText)"
        )
    }

    public func initialHealthWarningPlan(
        snapshot: RuntimeHealthSnapshot
    ) -> ApplyRuntimeBundleInitialHealthWarningPlan {
        let decision = initialHealthDecision(snapshot: snapshot)
        guard let warningMessage = decision.warningMessage else {
            return .continueWithoutWarning
        }
        return .continueWithWarning(warningMessage)
    }

    public func planApplyBundle(for preflight: ApplyBundlePreflightContext) -> ApplyRuntimeBundlePlan {
        ApplyRuntimeBundlePlan(
            operationPlan: RuntimeOperationPlans.applyBundle(updatesRootfsBase: preflight.updatesRootfsBase)
        )
    }

    public func applyBundleStartedPlan(inputPath: String) -> UpdateRuntimeLoggedStatusPlan {
        UpdateRuntimeLoggedStatusPlan(
            logMessage: "bundle apply started input=\(inputPath)",
            status: .updating,
            operation: .applyBundle,
            statusMessage: "bundle apply started"
        )
    }

    public func applyBundlePreflightFailedStatusPlan(reason: String) -> UpdateRuntimeStatusPlan {
        UpdateRuntimeStatusPlan(
            status: .critical,
            operation: .applyBundle,
            message: "bundle apply preflight failed: \(reason)"
        )
    }

    public func applyBundleRollbackStartedPlan(reason: String) -> UpdateRuntimeLoggedStatusPlan {
        UpdateRuntimeLoggedStatusPlan(
            logMessage: "bundle apply failed; rolling back error=\(reason)",
            status: .recovering,
            operation: .applyBundle,
            statusMessage: "bundle apply failed; rolling back: \(reason)"
        )
    }

    public func applyBundleRollbackCompletedStatusPlan(reason: String) -> UpdateRuntimeStatusPlan {
        UpdateRuntimeStatusPlan(
            status: .degraded,
            operation: .applyBundle,
            message: "bundle apply failed; rollback completed: \(reason)"
        )
    }

    public func applyBundleFailureRecoveryPlan(
        preflight: ApplyBundlePreflightContext,
        applyFailureReason: String
    ) -> ApplyRuntimeBundleFailureRecoveryPlan {
        ApplyRuntimeBundleFailureRecoveryPlan(
            backup: preflight.backup,
            restartPolicy: preflight.restartPolicy,
            rollbackStartedPlan: applyBundleRollbackStartedPlan(reason: applyFailureReason),
            rollbackCompletedPlan: applyBundleRollbackCompletedStatusPlan(reason: applyFailureReason)
        )
    }

    public func applyBundleRollbackFailedPlan(reason: String) -> UpdateRuntimeLoggedStatusPlan {
        UpdateRuntimeLoggedStatusPlan(
            logMessage: "bundle apply rollback failed error=\(reason)",
            status: .critical,
            operation: .applyBundle,
            statusMessage: "bundle apply failed and rollback failed: \(reason)"
        )
    }

    public func applyBundleCompletedPlan(version: String, stagedBundlePath: String) -> UpdateRuntimeLoggedStatusPlan {
        UpdateRuntimeLoggedStatusPlan(
            logMessage: "bundle applied path=\(stagedBundlePath)",
            status: .healthy,
            operation: .applyBundle,
            statusMessage: "bundle applied: \(version)"
        )
    }

    public func applyBundleArtifactCleanupFailedLogMessage(reason: String) -> String {
        "runtime artifact cleanup failed after bundle apply error=\(reason)"
    }

    public func applyBundleRollbackFailureServiceRestartFailedLogMessage(reason: String) -> String {
        "failed to restart runtime services after rollback failure error=\(reason)"
    }

    public func applyBundleLogDirectoryPreparationFailedLogMessage(reason: String) -> String {
        "bundle apply log directory preparation failed error=\(reason)"
    }

    public func applyBundleLogRotationFailedLogMessage(reason: String) -> String {
        "bundle apply log rotation failed error=\(reason)"
    }

    public func mutableVMDiskPreservedLogMessage(path: String) -> String {
        "mutable VM disk preserved path=\(path)"
    }

    public func preflightManifestPlan(
        stagedBundle: URL,
        manifest: UpdateBundleManifest
    ) -> ApplyRuntimeBundlePreflightManifestPlan {
        ApplyRuntimeBundlePreflightManifestPlan(
            stagedRootfs: manifest.artifacts.contains { $0.type == .rootfsBase }
                ? stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase)
                : nil,
            manifestLogMessage: "bundle apply manifest version=\(manifest.version) runtimeVersion=\(manifest.runtimeVersion) artifacts=\(manifest.artifacts.count) migrations=\(manifest.migrations.count)",
            backupReason: "before-\(manifest.version)",
            backupStartedLogMessage: "creating managed backup reason=before-\(manifest.version)"
        )
    }

    public func preflightCapabilityPlan(
        manifest: UpdateBundleManifest,
        restartPolicy: RuntimeServiceRestartPolicy
    ) -> ApplyRuntimeBundlePreflightCapabilityPlan {
        var instructions: [ApplyRuntimeBundlePreflightCapabilityInstruction] = []
        if restartPolicy.restartVM {
            instructions.append(.requireRuntimeDiskHealthAllowsUpdate)
            instructions.append(.requireGuestCapability(.prepareUpdateShutdown))
        }
        if manifest.artifacts.contains(where: { $0.type == .guestDeploy }) {
            instructions.append(.requireGuestCapability(.activateUpdate))
        }

        return ApplyRuntimeBundlePreflightCapabilityPlan(
            instructions: instructions,
            serviceRestartLogMessage: "runtime services before update vm=\(loadedText(restartPolicy.restartVM)) guestLogSync=\(loadedText(restartPolicy.restartGuestLogSync)) proxy=\(loadedText(restartPolicy.restartProxy)) watchdog=\(loadedText(restartPolicy.restartWatchdog))"
        )
    }

    public func storageRequirement(
        stagedBundleBytes: UInt64,
        rootfsStorage: RuntimeUpdateRootfsStorageInput,
        marginBytes: UInt64
    ) -> RuntimeUpdateStorageRequirement {
        RuntimeUpdatePreflightPolicy.storageRequirement(
            stagedBundleBytes: stagedBundleBytes,
            rootfsStorage: rootfsStorage,
            marginBytes: marginBytes
        )
    }

    public func storagePreflightStagedBundleLogMessage(stagedBundleBytes: UInt64) -> String {
        "bundle apply storage preflight stagedBundle=\(formatBytes(stagedBundleBytes))"
    }

    public func replacingRootfsStoragePreflightPlan(
        installedRootfsBytes: UInt64,
        incomingRootfsBytes: UInt64
    ) -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
        ApplyRuntimeBundleRootfsStoragePreflightPlan(
            rootfsStorage: .replacing(
                installedRootfsBytes: installedRootfsBytes,
                incomingRootfsBytes: incomingRootfsBytes
            ),
            logMessage: "bundle apply storage preflight installedRootfs=\(formatBytes(installedRootfsBytes)) incomingRootfs=\(formatBytes(incomingRootfsBytes))"
        )
    }

    public func unchangedRootfsStoragePreflightPlan() -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
        ApplyRuntimeBundleRootfsStoragePreflightPlan(
            rootfsStorage: .unchanged,
            logMessage: "bundle apply storage preflight rootfsBase=unchanged"
        )
    }

    public func rootfsStorageObservationPlan(
        stagedRootfs: URL?,
        rootfsBase: URL
    ) -> ApplyRuntimeBundleRootfsStorageObservationPlan {
        guard let stagedRootfs else {
            return .unchanged(unchangedRootfsStoragePreflightPlan())
        }
        return .replacing(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase)
    }

    public func rootfsStorageDecision(
        observation: ApplyRuntimeBundleRootfsStorageObservation
    ) -> ApplyRuntimeBundleRootfsStorageDecision {
        guard observation.stagedRootfsExists else {
            return .failed(message: missingFileFailureMessage(path: observation.stagedRootfs.path))
        }
        guard let installedRootfsBytes = observation.installedRootfsBytes,
              let incomingRootfsBytes = observation.incomingRootfsBytes
        else {
            return .failed(message: "missing rootfs storage observation")
        }
        return .planned(replacingRootfsStoragePreflightPlan(
            installedRootfsBytes: installedRootfsBytes,
            incomingRootfsBytes: incomingRootfsBytes
        ))
    }

    public func missingFileFailureMessage(path: String) -> String {
        "missing file: \(path)"
    }

    public func backupCreatedLogMessage(backupPath: String, backupBytes: UInt64) -> String {
        "backup created path=\(backupPath) size=\(formatBytes(backupBytes))"
    }

    public func stopExecutionPlan(
        restartPolicy: RuntimeServiceRestartPolicy,
        manifest: UpdateBundleManifest
    ) -> ApplyRuntimeBundleStopExecutionPlan {
        guard restartPolicy.restartVM else {
            return .stopServicesDirectly
        }
        return .prepareGuestShutdownAndStopServicesAfterPoweroff(manifest: manifest)
    }

    public func rootfsReplacementPlan(
        stagedRootfs: URL?,
        rootfsBase: URL
    ) -> ApplyRuntimeBundleRootfsReplacementPlan {
        guard let stagedRootfs else {
            return .skip(logMessage: "rootfs-base replacement skipped; bundle does not include rootfs-base")
        }
        return .replace(stagedRootfs: stagedRootfs, rootfsBase: rootfsBase)
    }

    public func capturedVMProcessBeforeGuestUpdateShutdownLogMessage(processID: pid_t) -> String {
        "captured VM process before guest update shutdown pid=\(processID)"
    }

    public func rootfsReplacementExecutionPlan(
        stagedRootfs: URL,
        rootfsBase: URL,
        stagedRootfsBytes: UInt64
    ) -> ApplyRuntimeBundleRootfsReplacementExecutionPlan {
        ApplyRuntimeBundleRootfsReplacementExecutionPlan(
            startedLogMessage: "replacing rootfs-base source=\(stagedRootfs.path) destination=\(rootfsBase.path) size=\(formatBytes(stagedRootfsBytes))",
            completedLogMessage: "rootfs-base replaced destination=\(rootfsBase.path)"
        )
    }

    public func rootfsReplacementExecutionPlan(
        observation: ApplyRuntimeBundleRootfsReplacementObservation
    ) -> ApplyRuntimeBundleRootfsReplacementExecutionPlan {
        rootfsReplacementExecutionPlan(
            stagedRootfs: observation.stagedRootfs,
            rootfsBase: observation.rootfsBase,
            stagedRootfsBytes: observation.stagedRootfsBytes
        )
    }

    public func applyBundleStepExecutionPlan(
        step: RuntimeWorkflowStep,
        preflight: ApplyBundlePreflightContext,
        rootfsBase: URL
    ) -> ApplyRuntimeBundleStepExecutionPlan {
        switch step {
        case .stopRuntimeServices:
            return .stopRuntimeServices(stopExecutionPlan(
                restartPolicy: preflight.restartPolicy,
                manifest: preflight.manifest
            ))
        case .replaceRootfsBase:
            return .replaceRootfsBase(rootfsReplacementPlan(
                stagedRootfs: preflight.stagedRootfs,
                rootfsBase: rootfsBase
            ))
        case .replaceUpdateArtifacts:
            return .replaceUpdateArtifacts(
                artifacts: preflight.manifest.artifacts,
                stagedBundle: preflight.stagedBundle
            )
        case .runMigrations:
            return .runMigrations(
                migrations: preflight.manifest.migrations,
                stagedBundle: preflight.stagedBundle
            )
        case .refreshCloudInitSeed:
            return .refreshCloudInitSeed(manifest: preflight.manifest)
        case .writeRuntimeVersion:
            return .writeRuntimeVersion(
                version: preflight.manifest.version,
                stagedBundle: preflight.stagedBundle
            )
        case .startRuntimeServices:
            return .startRuntimeServices(preflight.restartPolicy)
        case .activateGuestUpdate:
            return .activateGuestUpdate(manifest: preflight.manifest)
        case .waitRuntimeHealth:
            return .waitRuntimeHealth(preflight.restartPolicy)
        default:
            return .unsupported(failureMessage: unsupportedApplyBundleStepFailureMessage(step: step))
        }
    }

    public func unsupportedApplyBundleStepFailureMessage(step: RuntimeWorkflowStep) -> String {
        "unsupported command: apply-bundle step \(step.rawValue)"
    }

    public func unsupportedRollbackStepFailureMessage(step: RuntimeWorkflowStep) -> String {
        "unsupported command: rollback step \(step.rawValue)"
    }

    public func rollbackRootfsRestoreMissingBackupRootfsFailureMessage() -> String {
        "rollback rootfs restore requested without backup rootfs"
    }

    public func guestShutdownPreparationCleanupFailedLogMessage(reason: String) -> String {
        "guest shutdown preparation cleanup failed error=\(reason)"
    }

    public func diskHealthDecision(
        snapshot: RuntimeHealthSnapshot
    ) -> ApplyRuntimeBundleDiskHealthDecision {
        let blockers = RuntimeUpdatePreflightPolicy.blockingGuestStorageErrors(snapshot.vmErrors)
        guard !blockers.isEmpty else {
            return .allowed
        }

        let codes = blockers.map(\.rawValue).joined(separator: ",")
        return .blocked(
            blockers: blockers,
            logMessage: "bundle apply blocked by VM guest storage health errors=\(codes)",
            failureMessage: "VM disk health blocks update; run Repair VM Disk before applying update. errors=\(codes)"
        )
    }

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

    public func bundleVerificationStartedLogMessage(sourcePath: String) -> String {
        "bundle verification started path=\(sourcePath)"
    }

    public func bundleStageStartedLogMessage(sourcePath: String) -> String {
        "bundle stage started source=\(sourcePath)"
    }

    public func bundleMaterializationCleanupPlan(
        materialized: RuntimeMaterializedBundle
    ) -> RuntimeBundleMaterializationCleanupPlan {
        guard let temporaryRoot = materialized.temporaryRoot else {
            return .none
        }
        return .cleanupTemporaryRoot(temporaryRoot)
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

    public func guestActivationPlan(
        manifest: UpdateBundleManifest
    ) -> RuntimeGuestActivationPlan {
        let requiresActivation = manifest.artifacts.contains(where: { $0.type == .guestDeploy })
        guard requiresActivation else {
            return RuntimeGuestActivationPlan(
                requiresActivation: false,
                version: manifest.version,
                skippedLogMessage: "guest update activation not required",
                requestedLogMessage: nil,
                completedLogMessage: nil
            )
        }

        return RuntimeGuestActivationPlan(
            requiresActivation: true,
            version: manifest.version,
            skippedLogMessage: nil,
            requestedLogMessage: "guest update activation requested version=\(manifest.version)",
            completedLogMessage: "guest update activation completed version=\(manifest.version)"
        )
    }

    public func guestActivationExecutionPlan(
        manifest: UpdateBundleManifest
    ) -> RuntimeGuestActivationExecutionPlan {
        let requiresActivation = manifest.artifacts.contains(where: { $0.type == .guestDeploy })
        guard requiresActivation else {
            return .skip(logMessage: "guest update activation not required")
        }
        return .activate(
            version: manifest.version,
            requestedLogMessage: "guest update activation requested version=\(manifest.version)",
            completedLogMessage: "guest update activation completed version=\(manifest.version)"
        )
    }

    public func guestActivationRequest(
        plan: RuntimeGuestActivationPlan,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestActivationRequest? {
        guard plan.requiresActivation else {
            return nil
        }
        return RuntimeGuestActivationRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: plan.version
        )
    }

    public func guestActivationRequest(
        version: String,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestActivationRequest {
        RuntimeGuestActivationRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: version
        )
    }

    public func guestActivationVMStartPlan(
        isVMServiceLoaded: Bool
    ) -> RuntimeGuestActivationVMStartPlan {
        isVMServiceLoaded ? .alreadyLoaded : .startService
    }

    public func guestActivationWaitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for guest update activation result timeoutSeconds=\(timeoutSeconds)"
    }

    public func guestActivationWaitConfiguration(timeoutSeconds: Double) -> GuestActivationWaitConfiguration {
        GuestActivationWaitConfiguration(
            maxAttempts: Int(ceil(timeoutSeconds / 3.0)),
            progressEveryAttempts: 5
        )
    }

    public func guestActivationRequiredRequestMissingFailureMessage() -> String {
        "guest activation request missing for required activation"
    }

    public func guestActivationWaitResultPlan(
        _ result: GuestActivationWaitResult
    ) -> RuntimeGuestWaitResultPlan {
        switch result {
        case .completed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update activation result completed message=\(message)",
                failureMessage: nil
            )
        case .failed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update activation result failed message=\(message)",
                failureMessage: "runtime health check failed"
            )
        case .timedOut:
            return RuntimeGuestWaitResultPlan(
                logMessage: nil,
                failureMessage: "runtime health check failed"
            )
        }
    }

    public func guestActivationWaitResultExecutionPlan(
        _ result: GuestActivationWaitResult
    ) -> RuntimeGuestWaitResultExecutionPlan {
        switch result {
        case .completed(let message):
            return .completed(logMessage: "guest update activation result completed message=\(message)")
        case .failed(let message):
            return .failed(
                logMessage: "guest update activation result failed message=\(message)",
                failureMessage: "runtime health check failed"
            )
        case .timedOut:
            return .failedWithoutLog(failureMessage: "runtime health check failed")
        }
    }

    public func guestShutdownPlan(version: String) -> RuntimeGuestShutdownPlan {
        RuntimeGuestShutdownPlan(
            version: version,
            requestedLogMessage: "guest update shutdown requested version=\(version)",
            readyLogMessage: "guest update shutdown ready version=\(version)"
        )
    }

    public func guestShutdownExecutionPlan(version: String) -> RuntimeGuestShutdownExecutionPlan {
        .prepare(
            version: version,
            requestLog: "guest update shutdown requested version=\(version)",
            readyLog: "guest update shutdown ready version=\(version)"
        )
    }

    public func guestShutdownRequest(
        plan: RuntimeGuestShutdownPlan,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestShutdownRequest {
        RuntimeGuestShutdownRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: plan.version
        )
    }

    public func guestShutdownRequest(
        version: String,
        requestID: String,
        requestedAt: String
    ) -> RuntimeGuestShutdownRequest {
        RuntimeGuestShutdownRequest(
            id: requestID,
            requestedAt: requestedAt,
            version: version
        )
    }

    public func guestShutdownWaitStartedLogMessage(timeoutSeconds: Double) -> String {
        "waiting for guest update shutdown result timeoutSeconds=\(timeoutSeconds)"
    }

    public func guestShutdownWaitConfiguration(timeoutSeconds: Double) -> GuestShutdownWaitConfiguration {
        GuestShutdownWaitConfiguration(
            maxAttempts: Int(ceil(timeoutSeconds / 3.0)),
            progressEveryAttempts: 5
        )
    }

    public func guestShutdownWaitResultPlan(
        _ result: GuestShutdownWaitResult
    ) -> RuntimeGuestWaitResultPlan {
        switch result {
        case .ready(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update shutdown result ready message=\(message)",
                failureMessage: nil
            )
        case .failed(let message):
            return RuntimeGuestWaitResultPlan(
                logMessage: "guest update shutdown result failed message=\(message)",
                failureMessage: message
            )
        case .timedOut:
            return RuntimeGuestWaitResultPlan(
                logMessage: nil,
                failureMessage: "guest update shutdown timed out"
            )
        }
    }

    public func guestShutdownWaitResultExecutionPlan(
        _ result: GuestShutdownWaitResult
    ) -> RuntimeGuestWaitResultExecutionPlan {
        switch result {
        case .ready(let message):
            return .completed(logMessage: "guest update shutdown result ready message=\(message)")
        case .failed(let message):
            return .failed(
                logMessage: "guest update shutdown result failed message=\(message)",
                failureMessage: message
            )
        case .timedOut:
            return .failedWithoutLog(failureMessage: "guest update shutdown timed out")
        }
    }

    public func guestCapabilityDecision(
        loadResult: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>,
        capability: RuntimeGuestCapabilityRequirement
    ) -> RuntimeGuestCapabilityDecision {
        switch loadResult {
        case .loaded(let state):
            guard let capabilities = state.capabilities,
                  capability.isSupported(by: capabilities)
            else {
                return RuntimeGuestCapabilityDecision(
                    isSupported: false,
                    failure: .missingCapability(capability.rawValue)
                )
            }
            return RuntimeGuestCapabilityDecision(isSupported: true, failure: nil)
        case .missing:
            return RuntimeGuestCapabilityDecision(
                isSupported: false,
                failure: .missingRuntimeState(capability.rawValue)
            )
        case .failed(let message):
            return RuntimeGuestCapabilityDecision(
                isSupported: false,
                failure: .runtimeStateReadFailed(
                    capability: capability.rawValue,
                    reason: message
                )
            )
        }
    }

    public func guestCapabilityRequirementPlan(
        loadResult: RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>,
        capability: RuntimeGuestCapabilityRequirement
    ) -> RuntimeGuestCapabilityRequirementPlan {
        let decision = guestCapabilityDecision(
            loadResult: loadResult,
            capability: capability
        )
        guard let failure = decision.failure else {
            return .supported
        }
        return .failed(failure)
    }

    private func loadedText(_ loaded: Bool) -> String {
        loaded ? "loaded" : "not-loaded"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
