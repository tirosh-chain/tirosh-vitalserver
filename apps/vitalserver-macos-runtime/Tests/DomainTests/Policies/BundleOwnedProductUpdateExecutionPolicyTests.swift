import Contracts
import Domain
import XCTest

final class BundleOwnedProductUpdateExecutionPolicyTests: XCTestCase {
    func testAcceptsCorrelatedSuccessfulReceipt() throws {
        let request = effectRequest()
        let receipt = receipt(for: request, state: .succeeded)

        try BundleOwnedProductUpdateExecutionPolicy.validate(
            receipt: receipt,
            request: request
        )
    }

    func testRejectsReceiptForDifferentArtifact() {
        let request = effectRequest()
        let invalid = ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: request.updateId,
            layer: request.layer,
            effectExecutorId: request.effectExecutor.id,
            operation: request.operation,
            artifactSHA256: digest("f"),
            state: .succeeded,
            observedAt: "2026-07-28T10:00:00Z",
            evidence: evidence(),
            issue: nil
        )

        XCTAssertThrowsError(
            try BundleOwnedProductUpdateExecutionPolicy.validate(
                receipt: invalid,
                request: request
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdateExecutionPolicyError,
                .receiptCorrelationMismatch
            )
        }
    }

    func testInvalidCompletedReceiptBecomesExplicitUnavailableEvidence() {
        let request = effectRequest()
        let invalid = ProductUpdateLayerEffectReceipt(
            schemaVersion: "unknown",
            updateId: request.updateId,
            layer: request.layer,
            effectExecutorId: request.effectExecutor.id,
            operation: request.operation,
            artifactSHA256: request.artifact.sha256,
            state: .succeeded,
            observedAt: "2026-07-28T10:00:00Z",
            evidence: evidence(),
            issue: nil
        )

        let evaluated = BundleOwnedProductUpdateExecutionPolicy.evaluate(
            request: request,
            result: .completed(invalid),
            observedAt: "2026-07-28T10:01:00Z"
        )

        XCTAssertEqual(evaluated.state, .unavailable)
        XCTAssertEqual(evaluated.issue?.code, "layer-effect-receipt-invalid")
        XCTAssertTrue(evaluated.issue?.retryable == true)
    }

    func testRejectsSuccessReportWithIncompleteApplyReceipts() {
        let invocation = invocation()
        let plan = ProductUpdateExecutionPlan(
            updateId: invocation.updateId,
            specificationId: "specification-42",
            layerPlan: [layerPlan(.container), layerPlan(.guestRuntime)]
        )
        let request = effectRequest()
        let report = ProductUpdateExecutionReport(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: invocation.updateId,
            requestId: invocation.requestId,
            bootstrapEnvelopeId: invocation.bootstrapEnvelopeId,
            updateSpecificationSHA256:
                invocation.updateSpecificationSHA256,
            state: .succeeded,
            startedAt: "2026-07-28T10:00:00Z",
            finishedAt: "2026-07-28T10:01:00Z",
            applyReceipts: [receipt(for: request, state: .succeeded)],
            rollbackReceipts: [],
            rollback: ProductUpdateRollbackEvidence(
                state: .notRequired,
                observedAt: "2026-07-28T10:01:00Z",
                evidence: nil,
                issue: nil
            ),
            failure: nil
        )

        XCTAssertThrowsError(
            try BundleOwnedProductUpdateExecutionPolicy.validate(
                report: report,
                invocation: invocation,
                plan: plan
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdateExecutionPolicyError,
                .invalidReportOutcome
            )
        }
    }

    private func effectRequest() -> ProductUpdateLayerEffectRequest {
        let plan = layerPlan(.container)
        return BundleOwnedProductUpdateExecutionPolicy.makeRequest(
            updateId: "update-42",
            layerPlan: plan,
            operation: .apply,
            artifact: plan.artifact
        )
    }

    private func receipt(
        for request: ProductUpdateLayerEffectRequest,
        state: ProductUpdateLayerEffectState
    ) -> ProductUpdateLayerEffectReceipt {
        ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: request.updateId,
            layer: request.layer,
            effectExecutorId: request.effectExecutor.id,
            operation: request.operation,
            artifactSHA256: request.artifact.sha256,
            state: state,
            observedAt: "2026-07-28T10:00:00Z",
            evidence: evidence(),
            issue: state == .succeeded ? nil : ProductUpdateIssue(
                code: "effect-failed",
                message: "effect failed",
                retryable: false,
                dependency: "fixture"
            )
        )
    }

    private func evidence() -> ProductUpdateEvidenceReference {
        ProductUpdateEvidenceReference(kind: "fixture", id: "evidence-42")
    }

    private func invocation() -> UpdateBootstrapHandoffInvocation {
        UpdateBootstrapHandoffInvocation(
            schemaVersion: UpdateBootstrapHandoffPolicy.schemaVersion,
            updateId: "update-42",
            operationId: "operation-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            bootstrapSignedSHA256: digest("d"),
            updateSpecificationSHA256: digest("e"),
            layerOrder: [.container, .guestRuntime],
            expectedJournalRevision: 3,
            updaterRelativePath: "payload/updater",
            specificationRelativePath: "payload/specification.json",
            completionReceiptRelativePath: "handoff/completion-receipt.json"
        )
    }

    private func layerPlan(_ layer: UpdateLayer) -> ProductUpdateLayerPlan {
        ProductUpdateLayerPlan(
            layer: layer,
            dependsOn: [],
            artifact: artifact("\(layer.rawValue)-artifact", "a"),
            effectExecutor: ProductUpdateLayerEffectExecutor(
                id: "\(layer.rawValue)-executor",
                relativePath: "payload/\(layer.rawValue)-executor",
                sha256: digest("b"),
                sizeBytes: 1,
                mediaType:
                    BundleOwnedProductUpdatePlanner.effectExecutorMediaType,
                configurationArtifact: artifact(
                    "\(layer.rawValue)-configuration",
                    "c",
                    mediaType: BundleOwnedProductUpdatePlanner
                        .effectConfigurationMediaType
                )
            ),
            rollback: ProductUpdateLayerRollbackPlan(
                state: .unsupported,
                artifact: nil,
                reason: "not published"
            )
        )
    }

    private func artifact(
        _ id: String,
        _ character: Character,
        mediaType: String = "application/octet-stream"
    ) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: id,
            relativePath: "payload/\(id)",
            sha256: digest(character),
            sizeBytes: 1,
            mediaType: mediaType
        )
    }

    private func digest(_ character: Character) -> String {
        String(repeating: character, count: 64)
    }
}
