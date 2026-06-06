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

public struct ApplyRuntimeBundlePlan: Equatable, Sendable {
    public let operationPlan: RuntimeOperationPlan

    public init(operationPlan: RuntimeOperationPlan) {
        self.operationPlan = operationPlan
    }
}

public struct ApplyRuntimeBundlePreflightCapabilityPlan: Equatable, Sendable {
    public let requiresRuntimeDiskHealthCheck: Bool
    public let requiredGuestCapabilities: [RuntimeGuestCapabilityRequirement]
    public let serviceRestartLogMessage: String

    public init(
        requiresRuntimeDiskHealthCheck: Bool,
        requiredGuestCapabilities: [RuntimeGuestCapabilityRequirement],
        serviceRestartLogMessage: String
    ) {
        self.requiresRuntimeDiskHealthCheck = requiresRuntimeDiskHealthCheck
        self.requiredGuestCapabilities = requiredGuestCapabilities
        self.serviceRestartLogMessage = serviceRestartLogMessage
    }
}

public struct ApplyRuntimeBundleDiskHealthDecision: Equatable, Sendable {
    public let canApplyUpdate: Bool
    public let blockers: [RuntimeVMError]
    public let blockedLogMessage: String?
    public let failureMessage: String?

    public init(
        canApplyUpdate: Bool,
        blockers: [RuntimeVMError],
        blockedLogMessage: String?,
        failureMessage: String?
    ) {
        self.canApplyUpdate = canApplyUpdate
        self.blockers = blockers
        self.blockedLogMessage = blockedLogMessage
        self.failureMessage = failureMessage
    }
}

public struct RollbackRuntimePlan: Equatable, Sendable {
    public let operationPlan: RuntimeOperationPlan

    public init(operationPlan: RuntimeOperationPlan) {
        self.operationPlan = operationPlan
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

public struct UpdateRuntimeUseCase {
    public init() {}

    public func initialHealthDecision(
        snapshot: RuntimeHealthSnapshot,
        reasonText: String
    ) -> ApplyRuntimeBundleInitialHealthDecision {
        guard !RuntimeHealthSnapshotPolicy.isHealthy(snapshot) else {
            return ApplyRuntimeBundleInitialHealthDecision(
                shouldWarn: false,
                warningMessage: nil
            )
        }
        return ApplyRuntimeBundleInitialHealthDecision(
            shouldWarn: true,
            warningMessage: "bundle apply preflight warning runtime unhealthy reasons=\(reasonText)"
        )
    }

    public func planApplyBundle(for preflight: ApplyBundlePreflightContext) -> ApplyRuntimeBundlePlan {
        ApplyRuntimeBundlePlan(
            operationPlan: RuntimeOperationPlans.applyBundle(updatesRootfsBase: preflight.updatesRootfsBase)
        )
    }

    public func preflightCapabilityPlan(
        manifest: UpdateBundleManifest,
        restartPolicy: RuntimeServiceRestartPolicy
    ) -> ApplyRuntimeBundlePreflightCapabilityPlan {
        var capabilities: [RuntimeGuestCapabilityRequirement] = []
        if restartPolicy.restartVM {
            capabilities.append(.prepareUpdateShutdown)
        }
        if manifest.artifacts.contains(where: { $0.type == .guestDeploy }) {
            capabilities.append(.activateUpdate)
        }

        return ApplyRuntimeBundlePreflightCapabilityPlan(
            requiresRuntimeDiskHealthCheck: restartPolicy.restartVM,
            requiredGuestCapabilities: capabilities,
            serviceRestartLogMessage: "runtime services before update vm=\(loadedText(restartPolicy.restartVM)) guestLogSync=\(loadedText(restartPolicy.restartGuestLogSync)) proxy=\(loadedText(restartPolicy.restartProxy)) watchdog=\(loadedText(restartPolicy.restartWatchdog))"
        )
    }

    public func diskHealthDecision(
        snapshot: RuntimeHealthSnapshot
    ) -> ApplyRuntimeBundleDiskHealthDecision {
        let blockers = RuntimeUpdatePreflightPolicy.blockingGuestStorageErrors(snapshot.vmErrors)
        guard !blockers.isEmpty else {
            return ApplyRuntimeBundleDiskHealthDecision(
                canApplyUpdate: true,
                blockers: [],
                blockedLogMessage: nil,
                failureMessage: nil
            )
        }

        let codes = blockers.map(\.rawValue).joined(separator: ",")
        return ApplyRuntimeBundleDiskHealthDecision(
            canApplyUpdate: false,
            blockers: blockers,
            blockedLogMessage: "bundle apply blocked by VM guest storage health errors=\(codes)",
            failureMessage: "VM disk health blocks update; run Repair VM Disk before applying update. errors=\(codes)"
        )
    }

    public func planRollback(for preflight: RollbackPreflightContext) -> RollbackRuntimePlan {
        RollbackRuntimePlan(
            operationPlan: RuntimeOperationPlans.rollback(restoresRootfsBase: preflight.restoresRootfsBase)
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

    public func guestShutdownPlan(version: String) -> RuntimeGuestShutdownPlan {
        RuntimeGuestShutdownPlan(
            version: version,
            requestedLogMessage: "guest update shutdown requested version=\(version)",
            readyLogMessage: "guest update shutdown ready version=\(version)"
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

    private func loadedText(_ loaded: Bool) -> String {
        loaded ? "loaded" : "not-loaded"
    }
}
