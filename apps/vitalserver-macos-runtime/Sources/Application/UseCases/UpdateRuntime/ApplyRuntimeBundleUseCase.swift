import Contracts
import Domain
import Foundation

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

public struct ApplyRuntimeBundlePreflightFailurePlan: Equatable, Sendable {
    public let statusPlan: UpdateRuntimeStatusPlan

    public init(statusPlan: UpdateRuntimeStatusPlan) {
        self.statusPlan = statusPlan
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

public struct ApplyRuntimeBundleUseCase {
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

    public func applyBundlePreflightFailurePlan(reason: String) -> ApplyRuntimeBundlePreflightFailurePlan {
        ApplyRuntimeBundlePreflightFailurePlan(
            statusPlan: applyBundlePreflightFailedStatusPlan(reason: reason)
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

    public func guestShutdownPreparationCleanupFailedLogMessage(reason: String) -> String {
        "guest shutdown preparation cleanup failed error=\(reason)"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
