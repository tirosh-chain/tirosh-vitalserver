import Application
import Contracts

public enum ExecuteBundleOwnedProductUpdateWorkflowError:
    Error, Equatable, Sendable
{
    case failedEffectHasNoIssue(layer: UpdateLayer)
}

public struct ExecuteBundleOwnedProductUpdateWorkflowOperations {
    public let plan: (
        UpdateBootstrapHandoffInvocation,
        ProductUpdateSpecification
    ) throws -> ProductUpdateExecutionPlan
    public let makeRequest: (
        String,
        ProductUpdateLayerPlan,
        ProductUpdateLayerEffectOperation,
        UpdateBootstrapArtifact
    ) -> ProductUpdateLayerEffectRequest
    public let execute: (
        ProductUpdateLayerEffectRequest
    ) -> ProductUpdateLayerEffectExecutionResult
    public let evaluate: (
        ProductUpdateLayerEffectRequest,
        ProductUpdateLayerEffectExecutionResult,
        String
    ) -> ProductUpdateLayerEffectReceipt
    public let validateReport: (
        ProductUpdateExecutionReport,
        UpdateBootstrapHandoffInvocation,
        ProductUpdateExecutionPlan
    ) throws -> Void
    public let now: () -> String

    public init(
        plan: @escaping (
            UpdateBootstrapHandoffInvocation,
            ProductUpdateSpecification
        ) throws -> ProductUpdateExecutionPlan,
        makeRequest: @escaping (
            String,
            ProductUpdateLayerPlan,
            ProductUpdateLayerEffectOperation,
            UpdateBootstrapArtifact
        ) -> ProductUpdateLayerEffectRequest,
        execute: @escaping (
            ProductUpdateLayerEffectRequest
        ) -> ProductUpdateLayerEffectExecutionResult,
        evaluate: @escaping (
            ProductUpdateLayerEffectRequest,
            ProductUpdateLayerEffectExecutionResult,
            String
        ) -> ProductUpdateLayerEffectReceipt,
        validateReport: @escaping (
            ProductUpdateExecutionReport,
            UpdateBootstrapHandoffInvocation,
            ProductUpdateExecutionPlan
        ) throws -> Void,
        now: @escaping () -> String
    ) {
        self.plan = plan
        self.makeRequest = makeRequest
        self.execute = execute
        self.evaluate = evaluate
        self.validateReport = validateReport
        self.now = now
    }
}

public struct ExecuteBundleOwnedProductUpdateWorkflow {
    public init() {}

    public func run(
        invocation: UpdateBootstrapHandoffInvocation,
        specification: ProductUpdateSpecification,
        operations: ExecuteBundleOwnedProductUpdateWorkflowOperations
    ) throws -> ProductUpdateExecutionReport {
        let plan = try operations.plan(invocation, specification)
        let startedAt = operations.now()
        var applyReceipts: [ProductUpdateLayerEffectReceipt] = []
        var applied: [ProductUpdateLayerPlan] = []

        for layerPlan in plan.layerPlan {
            let receipt = execute(
                updateId: plan.updateId,
                layerPlan: layerPlan,
                operation: .apply,
                artifact: layerPlan.artifact,
                operations: operations
            )
            applyReceipts.append(receipt)
            if receipt.state == .succeeded {
                applied.append(layerPlan)
                continue
            }
            guard let issue = receipt.issue else {
                throw ExecuteBundleOwnedProductUpdateWorkflowError
                    .failedEffectHasNoIssue(layer: layerPlan.layer)
            }
            let rollbackResult = rollback(
                updateId: plan.updateId,
                applied: applied,
                operations: operations
            )
            let report = ProductUpdateExecutionReport(
                schemaVersion: ProductUpdateExecutionContract.schemaVersion,
                updateId: invocation.updateId,
                requestId: invocation.requestId,
                bootstrapEnvelopeId: invocation.bootstrapEnvelopeId,
                updateSpecificationSHA256:
                    invocation.updateSpecificationSHA256,
                state: .failed,
                startedAt: startedAt,
                finishedAt: operations.now(),
                applyReceipts: applyReceipts,
                rollbackReceipts: rollbackResult.receipts,
                rollback: rollbackResult.evidence,
                failure: issue
            )
            try operations.validateReport(report, invocation, plan)
            return report
        }

        let report = ProductUpdateExecutionReport(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: invocation.updateId,
            requestId: invocation.requestId,
            bootstrapEnvelopeId: invocation.bootstrapEnvelopeId,
            updateSpecificationSHA256: invocation.updateSpecificationSHA256,
            state: .succeeded,
            startedAt: startedAt,
            finishedAt: operations.now(),
            applyReceipts: applyReceipts,
            rollbackReceipts: [],
            rollback: ProductUpdateRollbackEvidence(
                state: .notRequired,
                observedAt: operations.now(),
                evidence: nil,
                issue: nil
            ),
            failure: nil
        )
        try operations.validateReport(report, invocation, plan)
        return report
    }

    private func execute(
        updateId: String,
        layerPlan: ProductUpdateLayerPlan,
        operation: ProductUpdateLayerEffectOperation,
        artifact: UpdateBootstrapArtifact,
        operations: ExecuteBundleOwnedProductUpdateWorkflowOperations
    ) -> ProductUpdateLayerEffectReceipt {
        let request = operations.makeRequest(
            updateId,
            layerPlan,
            operation,
            artifact
        )
        return operations.evaluate(
            request,
            operations.execute(request),
            operations.now()
        )
    }

    private func rollback(
        updateId: String,
        applied: [ProductUpdateLayerPlan],
        operations: ExecuteBundleOwnedProductUpdateWorkflowOperations
    ) -> (
        evidence: ProductUpdateRollbackEvidence,
        receipts: [ProductUpdateLayerEffectReceipt]
    ) {
        guard !applied.isEmpty else {
            return (
                ProductUpdateRollbackEvidence(
                    state: .notRequired,
                    observedAt: operations.now(),
                    evidence: nil,
                    issue: nil
                ),
                []
            )
        }
        var receipts: [ProductUpdateLayerEffectReceipt] = []
        for layerPlan in applied.reversed() {
            guard layerPlan.rollback.state == .available,
                  let artifact = layerPlan.rollback.artifact else {
                return (
                    ProductUpdateRollbackEvidence(
                        state: .notAttempted,
                        observedAt: operations.now(),
                        evidence: nil,
                        issue: ProductUpdateIssue(
                            code: "rollback-artifact-unsupported",
                            message: layerPlan.rollback.reason
                                ?? "Rollback is not available.",
                            retryable: false,
                            dependency: "bundle-owned-layer-effect-executor"
                        )
                    ),
                    receipts
                )
            }
            let receipt = execute(
                updateId: updateId,
                layerPlan: layerPlan,
                operation: .rollback,
                artifact: artifact,
                operations: operations
            )
            receipts.append(receipt)
            guard receipt.state == .succeeded else {
                return (
                    ProductUpdateRollbackEvidence(
                        state: .failed,
                        observedAt: receipt.observedAt,
                        evidence: receipt.evidence,
                        issue: receipt.issue
                    ),
                    receipts
                )
            }
        }
        return (
            ProductUpdateRollbackEvidence(
                state: .succeeded,
                observedAt: operations.now(),
                evidence: ProductUpdateEvidenceReference(
                    kind: "product-update-rollback",
                    id: "\(updateId):rollback"
                ),
                issue: nil
            ),
            receipts
        )
    }
}
