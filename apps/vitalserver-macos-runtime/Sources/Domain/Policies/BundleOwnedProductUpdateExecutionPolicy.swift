import Contracts

public enum BundleOwnedProductUpdateExecutionPolicyError:
    Error, Equatable, Sendable
{
    case receiptCorrelationMismatch
    case invalidReceiptEvidence
    case succeededReceiptHasIssue
    case nonSuccessfulReceiptMissingIssue
    case reportCorrelationMismatch
    case reportLayerEvidenceMismatch
    case invalidReportOutcome
}

public enum BundleOwnedProductUpdateExecutionPolicy {
    public static let schemaVersion = ProductUpdateExecutionContract.schemaVersion

    public static func makeRequest(
        updateId: String,
        layerPlan: ProductUpdateLayerPlan,
        operation: ProductUpdateLayerEffectOperation,
        artifact: UpdateBootstrapArtifact
    ) -> ProductUpdateLayerEffectRequest {
        ProductUpdateLayerEffectRequest(
            updateId: updateId,
            layer: layerPlan.layer,
            effectExecutor: layerPlan.effectExecutor,
            operation: operation,
            artifact: artifact
        )
    }

    public static func evaluate(
        request: ProductUpdateLayerEffectRequest,
        result: ProductUpdateLayerEffectExecutionResult,
        observedAt: String
    ) -> ProductUpdateLayerEffectReceipt {
        switch result {
        case let .completed(receipt):
            do {
                try validate(receipt: receipt, request: request)
                return receipt
            } catch {
                return dependencyReceipt(
                    request: request,
                    state: .unavailable,
                    observedAt: observedAt,
                    code: "layer-effect-receipt-invalid",
                    message: "The declared executor produced invalid evidence."
                )
            }
        case let .unavailable(reason):
            return dependencyReceipt(
                request: request,
                state: .unavailable,
                observedAt: observedAt,
                code: "layer-effect-receipt-unavailable",
                message: reason
            )
        case let .failed(reason):
            return dependencyReceipt(
                request: request,
                state: .failed,
                observedAt: observedAt,
                code: "layer-effect-execution-failed",
                message: reason
            )
        }
    }

    public static func validate(
        receipt: ProductUpdateLayerEffectReceipt,
        request: ProductUpdateLayerEffectRequest
    ) throws {
        guard receipt.schemaVersion == schemaVersion,
              receipt.updateId == request.updateId,
              receipt.layer == request.layer,
              receipt.effectExecutorId == request.effectExecutor.id,
              receipt.operation == request.operation,
              receipt.artifactSHA256 == request.artifact.sha256 else {
            throw BundleOwnedProductUpdateExecutionPolicyError
                .receiptCorrelationMismatch
        }
        guard !receipt.observedAt.isEmpty,
              !receipt.evidence.kind.isEmpty,
              !receipt.evidence.id.isEmpty else {
            throw BundleOwnedProductUpdateExecutionPolicyError
                .invalidReceiptEvidence
        }
        if receipt.state == .succeeded {
            guard receipt.issue == nil else {
                throw BundleOwnedProductUpdateExecutionPolicyError
                    .succeededReceiptHasIssue
            }
        } else {
            guard let issue = receipt.issue,
                  !issue.code.isEmpty,
                  !issue.message.isEmpty,
                  !issue.dependency.isEmpty else {
                throw BundleOwnedProductUpdateExecutionPolicyError
                    .nonSuccessfulReceiptMissingIssue
            }
        }
    }

    public static func validate(
        report: ProductUpdateExecutionReport,
        invocation: UpdateBootstrapHandoffInvocation,
        plan: ProductUpdateExecutionPlan
    ) throws {
        guard report.schemaVersion == schemaVersion,
              report.updateId == invocation.updateId,
              report.requestId == invocation.requestId,
              report.bootstrapEnvelopeId == invocation.bootstrapEnvelopeId,
              report.updateSpecificationSHA256 ==
                invocation.updateSpecificationSHA256,
              !report.startedAt.isEmpty,
              !report.finishedAt.isEmpty else {
            throw BundleOwnedProductUpdateExecutionPolicyError
                .reportCorrelationMismatch
        }
        let expectedLayers = Array(
            plan.layerPlan.prefix(report.layerEvidence.count)
        ).map(\.layer)
        guard !report.layerEvidence.isEmpty,
              report.layerEvidence.count <= plan.layerPlan.count,
              report.layerEvidence.map(\.layer) == expectedLayers else {
            throw BundleOwnedProductUpdateExecutionPolicyError
                .reportLayerEvidenceMismatch
        }
        for (index, evidence) in report.layerEvidence.enumerated() {
            guard evidence.artifactSHA256 ==
                    plan.layerPlan[index].artifact.sha256,
                  !evidence.observedAt.isEmpty,
                  !evidence.evidence.kind.isEmpty,
                  !evidence.evidence.id.isEmpty,
                  (evidence.state == .succeeded) == (evidence.issue == nil) else {
                throw BundleOwnedProductUpdateExecutionPolicyError
                    .reportLayerEvidenceMismatch
            }
        }
        guard validRollbackEvidence(report.rollback) else {
            throw BundleOwnedProductUpdateExecutionPolicyError
                .invalidReportOutcome
        }
        switch report.state {
        case .succeeded:
            guard report.layerEvidence.count == plan.layerPlan.count,
                  report.layerEvidence.allSatisfy({ $0.state == .succeeded }),
                  report.rollback.state == .notRequired,
                  report.failure == nil else {
                throw BundleOwnedProductUpdateExecutionPolicyError
                    .invalidReportOutcome
            }
        case .failed:
            guard report.layerEvidence.last?.state != .succeeded,
                  report.failure != nil else {
                throw BundleOwnedProductUpdateExecutionPolicyError
                    .invalidReportOutcome
            }
        }
    }

    private static func validRollbackEvidence(
        _ rollback: ProductUpdateRollbackEvidence
    ) -> Bool {
        guard !rollback.observedAt.isEmpty else {
            return false
        }
        switch rollback.state {
        case .notRequired:
            return rollback.evidence == nil && rollback.issue == nil
        case .succeeded:
            return rollback.evidence != nil && rollback.issue == nil
        case .failed:
            return rollback.evidence != nil && rollback.issue != nil
        case .notAttempted:
            return rollback.issue != nil
        }
    }

    private static func dependencyReceipt(
        request: ProductUpdateLayerEffectRequest,
        state: ProductUpdateLayerEffectState,
        observedAt: String,
        code: String,
        message: String
    ) -> ProductUpdateLayerEffectReceipt {
        ProductUpdateLayerEffectReceipt(
            schemaVersion: schemaVersion,
            updateId: request.updateId,
            layer: request.layer,
            effectExecutorId: request.effectExecutor.id,
            operation: request.operation,
            artifactSHA256: request.artifact.sha256,
            state: state,
            observedAt: observedAt,
            evidence: ProductUpdateEvidenceReference(
                kind: "layer-effect-executor",
                id: [
                    request.updateId,
                    request.layer.rawValue,
                    request.operation.rawValue,
                ].joined(separator: ":")
            ),
            issue: ProductUpdateIssue(
                code: code,
                message: message,
                retryable: state == .unavailable,
                dependency: "bundle-owned-layer-effect-executor"
            )
        )
    }
}
