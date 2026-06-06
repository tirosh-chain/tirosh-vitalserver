import Contracts
import Domain
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

    private func loadedText(_ loaded: Bool) -> String {
        loaded ? "loaded" : "not-loaded"
    }
}
