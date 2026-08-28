import Contracts
import Domain

public struct PlanBundleOwnedProductUpdateUseCase {
    public init() {}

    public func execute(
        invocation: UpdateBootstrapHandoffInvocation,
        specification: ProductUpdateSpecification
    ) throws -> ProductUpdateExecutionPlan {
        try BundleOwnedProductUpdatePlanner.plan(
            invocation: invocation,
            specification: specification
        )
    }
}

public struct MakeProductUpdateLayerEffectRequestUseCase {
    public init() {}

    public func execute(
        updateId: String,
        layerPlan: ProductUpdateLayerPlan,
        operation: ProductUpdateLayerEffectOperation,
        artifact: UpdateBootstrapArtifact
    ) -> ProductUpdateLayerEffectRequest {
        BundleOwnedProductUpdateExecutionPolicy.makeRequest(
            updateId: updateId,
            layerPlan: layerPlan,
            operation: operation,
            artifact: artifact
        )
    }
}

public struct EvaluateProductUpdateLayerEffectUseCase {
    public init() {}

    public func execute(
        request: ProductUpdateLayerEffectRequest,
        result: ProductUpdateLayerEffectExecutionResult,
        observedAt: String
    ) -> ProductUpdateLayerEffectReceipt {
        BundleOwnedProductUpdateExecutionPolicy.evaluate(
            request: request,
            result: result,
            observedAt: observedAt
        )
    }
}

public struct ValidateProductUpdateExecutionReportUseCase {
    public init() {}

    public func execute(
        report: ProductUpdateExecutionReport,
        invocation: UpdateBootstrapHandoffInvocation,
        plan: ProductUpdateExecutionPlan
    ) throws {
        try BundleOwnedProductUpdateExecutionPolicy.validate(
            report: report,
            invocation: invocation,
            plan: plan
        )
    }
}
