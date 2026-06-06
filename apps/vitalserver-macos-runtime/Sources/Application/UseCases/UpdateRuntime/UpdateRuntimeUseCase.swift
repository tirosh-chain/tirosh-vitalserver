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

    public func planRollback(for preflight: RollbackPreflightContext) -> RollbackRuntimePlan {
        RollbackRuntimePlan(
            operationPlan: RuntimeOperationPlans.rollback(restoresRootfsBase: preflight.restoresRootfsBase)
        )
    }
}
