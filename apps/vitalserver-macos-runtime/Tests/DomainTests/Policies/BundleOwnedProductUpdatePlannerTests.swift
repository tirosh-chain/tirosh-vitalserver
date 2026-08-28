import Contracts
import Domain
import XCTest

final class BundleOwnedProductUpdatePlannerTests: XCTestCase {
    func testPlansExactlyTheBootstrapDeclaredLayerOrder() throws {
        let specification = specification(
            plans: [
                layer(.container),
                layer(.guestRuntime, dependsOn: [.container]),
                layer(
                    .hostPlatform,
                    dependsOn: [.container, .guestRuntime]
                ),
            ]
        )
        let invocation = invocation(
            layerOrder: [.container, .guestRuntime, .hostPlatform],
            payloadArtifacts:
                UpdateBootstrapBundleClosurePolicy.declaredArtifacts(
                    specification
                )
        )

        let plan = try BundleOwnedProductUpdatePlanner.plan(
            invocation: invocation,
            specification: specification
        )

        XCTAssertEqual(plan.updateId, "update-42")
        XCTAssertEqual(plan.specificationId, "specification-42")
        XCTAssertEqual(
            plan.layerPlan.map(\.layer),
            [.container, .guestRuntime, .hostPlatform]
        )
    }

    func testRejectsPayloadClosureThatOmitsDeclaredArtifact() {
        let specification = specification(plans: [layer(.container)])
        let declared = UpdateBootstrapBundleClosurePolicy.declaredArtifacts(
            specification
        )

        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(
                    layerOrder: [.container],
                    payloadArtifacts: Array(declared.dropFirst())
                ),
                specification: specification
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .payloadClosureMismatch(
                    missing: [declared[0].id],
                    unknown: []
                )
            )
        }
    }

    func testRejectsPayloadClosureWithUndeclaredArtifact() {
        let specification = specification(plans: [layer(.container)])
        let declared = UpdateBootstrapBundleClosurePolicy.declaredArtifacts(
            specification
        )

        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(
                    layerOrder: [.container],
                    payloadArtifacts: declared + [
                        artifact(
                            id: "undeclared-artifact",
                            path: "payload/undeclared.bin",
                            digestCharacter: "z"
                        )
                    ]
                ),
                specification: specification
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .payloadClosureMismatch(
                    missing: [],
                    unknown: ["undeclared-artifact"]
                )
            )
        }
    }

    func testRejectsPayloadClosureWhoseDeclaredArtifactIdentityDiffers() {
        let specification = specification(plans: [layer(.container)])
        var mismatched = UpdateBootstrapBundleClosurePolicy.declaredArtifacts(
            specification
        )
        let original = mismatched[0]
        mismatched[0] = artifact(
            id: original.id,
            path: original.relativePath,
            digestCharacter: "z"
        )

        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(
                    layerOrder: [.container],
                    payloadArtifacts: mismatched
                ),
                specification: specification
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .payloadClosureMismatch(
                    missing: [],
                    unknown: [original.id]
                )
            )
        }
    }

    func testRejectsSpecificationThatReordersBootstrapLayers() {
        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(
                    layerOrder: [.container, .guestRuntime]
                ),
                specification: specification(
                    plans: [layer(.guestRuntime), layer(.container)]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .layerOrderMismatch(
                    index: 0,
                    expected: .container,
                    actual: .guestRuntime
                )
            )
        }
    }

    func testRejectsHostPlatformBeforeTheFinalLayer() {
        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(
                    layerOrder: [.hostPlatform, .guestRuntime]
                ),
                specification: specification(
                    plans: [layer(.hostPlatform), layer(.guestRuntime)]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .hostPlatformIsNotFinal
            )
        }
    }

    func testAcceptsLeadingPunctuationIdentifiers() throws {
        let spec = specification(
            plans: [layer(.container, executorId: "-container-executor")],
            id: "_specification-42"
        )

        let plan = try BundleOwnedProductUpdatePlanner.plan(
            invocation: invocation(
                layerOrder: [.container],
                payloadArtifacts:
                    UpdateBootstrapBundleClosurePolicy.declaredArtifacts(spec),
                updateId: ".update-42"
            ),
            specification: spec
        )

        XCTAssertEqual(plan.updateId, ".update-42")
        XCTAssertEqual(plan.specificationId, "_specification-42")
    }

    func testRejectsColonInUpdateIdentifier() {
        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(
                    layerOrder: [.container],
                    updateId: "update:42"
                ),
                specification: specification(plans: [layer(.container)])
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .invalidInvocationIdentity
            )
        }
    }

    func testRejectsColonInSpecificationIdentifier() {
        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(layerOrder: [.container]),
                specification: specification(
                    plans: [layer(.container)],
                    id: "specification:42"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .invalidInvocationIdentity
            )
        }
    }

    func testRejectsColonInExecutorIdentifier() {
        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(layerOrder: [.container]),
                specification: specification(
                    plans: [layer(.container, executorId: "container:executor")]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .invalidEffectExecutor(layer: .container)
            )
        }
    }

    func testRejectsDependencyThatHasNotSucceededEarlier() {
        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(
                    layerOrder: [.container, .guestRuntime]
                ),
                specification: specification(
                    plans: [
                        layer(.container, dependsOn: [.guestRuntime]),
                        layer(.guestRuntime),
                    ]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .dependencyIsNotEarlier(
                    layer: .container,
                    dependency: .guestRuntime
                )
            )
        }
    }

    func testRejectsArtifactOutsidePayload() {
        var invalid = layer(.container)
        invalid = ProductUpdateLayerPlan(
            layer: invalid.layer,
            dependsOn: invalid.dependsOn,
            artifact: artifact(
                id: "container-apply",
                path: "../container.tar",
                digestCharacter: "a"
            ),
            effectExecutor: invalid.effectExecutor,
            rollback: invalid.rollback
        )

        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(layerOrder: [.container]),
                specification: specification(plans: [invalid])
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .invalidArtifact(layer: .container, role: "apply")
            )
        }
    }

    func testRejectsExecutorConfigurationThatAliasesAppliedArtifact() {
        let apply = artifact(
            id: "container-apply",
            path: "payload/container-apply.bin",
            digestCharacter: "a"
        )
        let invalid = ProductUpdateLayerPlan(
            layer: .container,
            dependsOn: [],
            artifact: apply,
            effectExecutor: ProductUpdateLayerEffectExecutor(
                id: "container-executor",
                relativePath: "payload/container-executor",
                sha256: digest("b"),
                sizeBytes: 10,
                mediaType: BundleOwnedProductUpdatePlanner
                    .effectExecutorMediaType,
                configurationArtifact: apply
            ),
            rollback: ProductUpdateLayerRollbackPlan(
                state: .unsupported,
                artifact: nil,
                reason: "rollback is not published"
            )
        )

        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(layerOrder: [.container]),
                specification: specification(plans: [invalid])
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .invalidEffectExecutor(layer: .container)
            )
        }
    }

    func testRejectsUnsupportedRollbackWithoutReason() {
        let valid = layer(.container)
        let invalid = ProductUpdateLayerPlan(
            layer: valid.layer,
            dependsOn: valid.dependsOn,
            artifact: valid.artifact,
            effectExecutor: valid.effectExecutor,
            rollback: ProductUpdateLayerRollbackPlan(
                state: .unsupported,
                artifact: nil,
                reason: nil
            )
        )

        XCTAssertThrowsError(
            try BundleOwnedProductUpdatePlanner.plan(
                invocation: invocation(layerOrder: [.container]),
                specification: specification(plans: [invalid])
            )
        ) { error in
            XCTAssertEqual(
                error as? BundleOwnedProductUpdatePlanningError,
                .invalidRollback(layer: .container)
            )
        }
    }

    private func invocation(
        layerOrder: [UpdateLayer],
        payloadArtifacts: [UpdateBootstrapArtifact] = [],
        updateId: String = "update-42"
    ) -> UpdateBootstrapHandoffInvocation {
        UpdateBootstrapHandoffInvocation(
            schemaVersion: UpdateBootstrapHandoffPolicy.schemaVersion,
            updateId: updateId,
            operationId: "operation-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            bootstrapSignedSHA256: digest("e"),
            updateSpecificationSHA256: digest("f"),
            guestControlBaseURL: "http://192.168.64.3:18330/",
            layerOrder: layerOrder,
            payloadArtifacts: payloadArtifacts,
            expectedJournalRevision: 3,
            updaterRelativePath: "payload/bin/next-updater",
            specificationRelativePath: "payload/specification.json",
            completionReceiptRelativePath:
                "handoff/completion-receipt.json"
        )
    }

    private func specification(
        plans: [ProductUpdateLayerPlan],
        id: String = "specification-42"
    ) -> ProductUpdateSpecification {
        ProductUpdateSpecification(
            schemaVersion: BundleOwnedProductUpdatePlanner
                .specificationSchemaVersion,
            id: id,
            bootstrapEnvelopeId: "envelope-42",
            layerPlan: plans
        )
    }

    private func layer(
        _ layer: UpdateLayer,
        dependsOn: [UpdateLayer] = [],
        executorId: String? = nil
    ) -> ProductUpdateLayerPlan {
        ProductUpdateLayerPlan(
            layer: layer,
            dependsOn: dependsOn,
            artifact: artifact(
                id: "\(layer.rawValue)-apply",
                path: "payload/\(layer.rawValue)-apply.bin",
                digestCharacter: character(for: layer, offset: 0)
            ),
            effectExecutor: ProductUpdateLayerEffectExecutor(
                id: executorId ?? "\(layer.rawValue)-executor",
                relativePath: "payload/\(layer.rawValue)-executor",
                sha256: digest(character(for: layer, offset: 1)),
                sizeBytes: 10,
                mediaType: BundleOwnedProductUpdatePlanner
                    .effectExecutorMediaType,
                configurationArtifact: artifact(
                    id: "\(layer.rawValue)-configuration",
                    path: "payload/\(layer.rawValue)-configuration.json",
                    digestCharacter: character(for: layer, offset: 2),
                    mediaType: BundleOwnedProductUpdatePlanner
                        .effectConfigurationMediaType
                )
            ),
            rollback: ProductUpdateLayerRollbackPlan(
                state: .available,
                artifact: artifact(
                    id: "\(layer.rawValue)-rollback",
                    path: "payload/\(layer.rawValue)-rollback.bin",
                    digestCharacter: character(for: layer, offset: 3)
                ),
                reason: nil
            )
        )
    }

    private func artifact(
        id: String,
        path: String,
        digestCharacter: Character,
        mediaType: String = "application/octet-stream"
    ) -> UpdateBootstrapArtifact {
        UpdateBootstrapArtifact(
            id: id,
            relativePath: path,
            sha256: digest(digestCharacter),
            sizeBytes: 10,
            mediaType: mediaType
        )
    }

    private func digest(_ character: Character) -> String {
        String(repeating: character, count: 64)
    }

    private func character(
        for layer: UpdateLayer,
        offset: Int
    ) -> Character {
        let values: [UpdateLayer: [Character]] = [
            .container: ["1", "2", "3", "4"],
            .guestRuntime: ["5", "6", "7", "8"],
            .hostPlatform: ["9", "a", "b", "c"],
        ]
        return values[layer]![offset]
    }
}
