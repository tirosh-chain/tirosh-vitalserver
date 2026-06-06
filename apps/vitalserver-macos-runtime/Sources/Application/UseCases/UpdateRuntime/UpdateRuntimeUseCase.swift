import Domain
import Errors

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
