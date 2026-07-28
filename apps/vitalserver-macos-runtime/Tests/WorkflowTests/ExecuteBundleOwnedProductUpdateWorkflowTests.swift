import Application
import Contracts
import Domain
import Workflow
import XCTest

final class ExecuteBundleOwnedProductUpdateWorkflowTests: XCTestCase {
    func testAppliesAllLayersInDeclaredOrder() throws {
        let fixture = Fixture()

        let report = try fixture.run(
            plans: [
                fixture.layer(.container),
                fixture.layer(.guestRuntime, dependsOn: [.container]),
            ],
            result: { request in
                .completed(fixture.receipt(request, state: .succeeded))
            }
        )

        XCTAssertEqual(report.state, .succeeded)
        XCTAssertEqual(
            fixture.requests.map { "\($0.operation.rawValue):\($0.layer.rawValue)" },
            ["apply:container", "apply:guest-runtime"]
        )
        XCTAssertEqual(report.rollback.state, .notRequired)
    }

    func testFailedLayerRollsBackAppliedLayersInReverseOrder() throws {
        let fixture = Fixture()

        let report = try fixture.run(
            plans: [
                fixture.layer(.container),
                fixture.layer(.guestRuntime, dependsOn: [.container]),
                fixture.layer(
                    .hostPlatform,
                    dependsOn: [.container, .guestRuntime]
                ),
            ],
            result: { request in
                if request.operation == .apply,
                   request.layer == .hostPlatform {
                    return .completed(
                        fixture.receipt(request, state: .failed)
                    )
                }
                return .completed(
                    fixture.receipt(request, state: .succeeded)
                )
            }
        )

        XCTAssertEqual(report.state, .failed)
        XCTAssertEqual(report.rollback.state, .succeeded)
        XCTAssertEqual(
            report.rollbackReceipts.map {
                "\($0.operation.rawValue):\($0.layer.rawValue):\($0.state.rawValue)"
            },
            [
                "rollback:guest-runtime:succeeded",
                "rollback:container:succeeded",
            ]
        )
        XCTAssertEqual(
            fixture.requests.map { "\($0.operation.rawValue):\($0.layer.rawValue)" },
            [
                "apply:container",
                "apply:guest-runtime",
                "apply:host-platform",
                "rollback:guest-runtime",
                "rollback:container",
            ]
        )
    }

    func testMissingExecutorEvidenceDoesNotBecomeSuccess() throws {
        let fixture = Fixture()

        let report = try fixture.run(
            plans: [fixture.layer(.container)],
            result: { _ in
                .unavailable(reason: "receipt file is missing")
            }
        )

        XCTAssertEqual(report.state, .failed)
        XCTAssertEqual(report.applyReceipts[0].state, .unavailable)
        XCTAssertEqual(
            report.failure?.code,
            "layer-effect-receipt-unavailable"
        )
    }
}

private final class Fixture {
    var requests: [ProductUpdateLayerEffectRequest] = []
    private var clockTick = 0

    func run(
        plans: [ProductUpdateLayerPlan],
        result: @escaping (
            ProductUpdateLayerEffectRequest
        ) -> ProductUpdateLayerEffectExecutionResult
    ) throws -> ProductUpdateExecutionReport {
        let invocation = invocation(layerOrder: plans.map(\.layer))
        let specification = ProductUpdateSpecification(
            schemaVersion:
                BundleOwnedProductUpdatePlanner.specificationSchemaVersion,
            id: "specification-42",
            bootstrapEnvelopeId: invocation.bootstrapEnvelopeId,
            layerPlan: plans
        )
        let planner = PlanBundleOwnedProductUpdateUseCase()
        let requestMaker = MakeProductUpdateLayerEffectRequestUseCase()
        let evaluator = EvaluateProductUpdateLayerEffectUseCase()
        let validator = ValidateProductUpdateExecutionReportUseCase()

        return try ExecuteBundleOwnedProductUpdateWorkflow().run(
            invocation: invocation,
            specification: specification,
            operations: ExecuteBundleOwnedProductUpdateWorkflowOperations(
                plan: { try planner.execute(invocation: $0, specification: $1) },
                makeRequest: {
                    requestMaker.execute(
                        updateId: $0,
                        layerPlan: $1,
                        operation: $2,
                        artifact: $3
                    )
                },
                execute: {
                    self.requests.append($0)
                    return result($0)
                },
                evaluate: {
                    evaluator.execute(
                        request: $0,
                        result: $1,
                        observedAt: $2
                    )
                },
                validateReport: {
                    try validator.execute(
                        report: $0,
                        invocation: $1,
                        plan: $2
                    )
                },
                now: { self.now() }
            )
        )
    }

    func layer(
        _ layer: UpdateLayer,
        dependsOn: [UpdateLayer] = []
    ) -> ProductUpdateLayerPlan {
        ProductUpdateLayerPlan(
            layer: layer,
            dependsOn: dependsOn,
            artifact: artifact("\(layer.rawValue)-apply", character(layer, 0)),
            effectExecutor: ProductUpdateLayerEffectExecutor(
                id: "\(layer.rawValue)-executor",
                relativePath: "payload/\(layer.rawValue)-executor",
                sha256: digest(character(layer, 1)),
                sizeBytes: 1,
                mediaType:
                    BundleOwnedProductUpdatePlanner.effectExecutorMediaType,
                configurationArtifact: artifact(
                    "\(layer.rawValue)-configuration",
                    character(layer, 2),
                    mediaType: BundleOwnedProductUpdatePlanner
                        .effectConfigurationMediaType
                )
            ),
            rollback: ProductUpdateLayerRollbackPlan(
                state: .available,
                artifact: artifact(
                    "\(layer.rawValue)-rollback",
                    character(layer, 3)
                ),
                reason: nil
            )
        )
    }

    func receipt(
        _ request: ProductUpdateLayerEffectRequest,
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
            observedAt: now(),
            evidence: ProductUpdateEvidenceReference(
                kind: "fixture-receipt",
                id: "\(request.layer.rawValue):\(request.operation.rawValue)"
            ),
            issue: state == .succeeded ? nil : ProductUpdateIssue(
                code: "fixture-effect-failed",
                message: "fixture effect failed",
                retryable: false,
                dependency: request.effectExecutor.id
            )
        )
    }

    private func invocation(
        layerOrder: [UpdateLayer]
    ) -> UpdateBootstrapHandoffInvocation {
        UpdateBootstrapHandoffInvocation(
            schemaVersion: UpdateBootstrapHandoffPolicy.schemaVersion,
            updateId: "update-42",
            operationId: "operation-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            bootstrapSignedSHA256: digest("d"),
            updateSpecificationSHA256: digest("e"),
            layerOrder: layerOrder,
            expectedJournalRevision: 3,
            updaterRelativePath: "payload/updater",
            specificationRelativePath: "payload/specification.json",
            completionReceiptRelativePath: "handoff/completion-receipt.json"
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

    private func character(
        _ layer: UpdateLayer,
        _ offset: Int
    ) -> Character {
        let values: [UpdateLayer: [Character]] = [
            .container: ["1", "2", "3", "4"],
            .guestRuntime: ["5", "6", "7", "8"],
            .hostPlatform: ["9", "a", "b", "c"],
        ]
        return values[layer]![offset]
    }

    private func digest(_ character: Character) -> String {
        String(repeating: character, count: 64)
    }

    private func now() -> String {
        defer { clockTick += 1 }
        return "2026-07-28T10:00:\(String(format: "%02d", clockTick))Z"
    }
}
