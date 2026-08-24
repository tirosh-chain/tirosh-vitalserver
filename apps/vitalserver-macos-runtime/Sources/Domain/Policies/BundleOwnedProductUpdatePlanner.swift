import Contracts

public enum BundleOwnedProductUpdatePlanningError: Error, Equatable, Sendable {
    case unsupportedInvocationSchema(String)
    case unsupportedSpecificationSchema(String)
    case invalidInvocationIdentity
    case emptyLayerOrder
    case envelopeMismatch(expected: String, actual: String)
    case layerCoverageMismatch
    case layerOrderMismatch(index: Int, expected: UpdateLayer, actual: UpdateLayer)
    case duplicateLayer(UpdateLayer)
    case hostPlatformIsNotFinal
    case duplicateDependency(layer: UpdateLayer, dependency: UpdateLayer)
    case dependencyIsNotEarlier(layer: UpdateLayer, dependency: UpdateLayer)
    case invalidArtifact(layer: UpdateLayer, role: String)
    case invalidEffectExecutor(layer: UpdateLayer)
    case conflictingArtifactIdentity(layer: UpdateLayer)
    case invalidRollback(layer: UpdateLayer)
    case payloadClosureMismatch(missing: [String], unknown: [String])
}

public enum BundleOwnedProductUpdatePlanner {
    public static let specificationSchemaVersion =
        "vitalserver.product-update-specification/v1"
    public static let effectExecutorMediaType =
        "application/vnd.tirosh.vitalserver.update-layer-effect-executor"
    public static let effectConfigurationMediaType =
        "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"

    public static func plan(
        invocation: UpdateBootstrapHandoffInvocation,
        specification: ProductUpdateSpecification
    ) throws -> ProductUpdateExecutionPlan {
        guard invocation.schemaVersion ==
                UpdateBootstrapHandoffPolicy.schemaVersion else {
            throw BundleOwnedProductUpdatePlanningError
                .unsupportedInvocationSchema(invocation.schemaVersion)
        }
        guard specification.schemaVersion == specificationSchemaVersion else {
            throw BundleOwnedProductUpdatePlanningError
                .unsupportedSpecificationSchema(specification.schemaVersion)
        }
        guard isIdentifier(invocation.updateId),
              isIdentifier(invocation.requestId),
              isIdentifier(invocation.bootstrapEnvelopeId),
              invocation.expectedJournalRevision > 0,
              isSHA256(invocation.updateSpecificationSHA256) else {
            throw BundleOwnedProductUpdatePlanningError.invalidInvocationIdentity
        }
        guard !invocation.layerOrder.isEmpty else {
            throw BundleOwnedProductUpdatePlanningError.emptyLayerOrder
        }
        guard isIdentifier(specification.id) else {
            throw BundleOwnedProductUpdatePlanningError.invalidInvocationIdentity
        }
        guard specification.bootstrapEnvelopeId ==
                invocation.bootstrapEnvelopeId else {
            throw BundleOwnedProductUpdatePlanningError.envelopeMismatch(
                expected: invocation.bootstrapEnvelopeId,
                actual: specification.bootstrapEnvelopeId
            )
        }
        guard specification.layerPlan.count == invocation.layerOrder.count else {
            throw BundleOwnedProductUpdatePlanningError.layerCoverageMismatch
        }

        var seen = Set<UpdateLayer>()
        for (index, layerPlan) in specification.layerPlan.enumerated() {
            let expected = invocation.layerOrder[index]
            guard layerPlan.layer == expected else {
                throw BundleOwnedProductUpdatePlanningError.layerOrderMismatch(
                    index: index,
                    expected: expected,
                    actual: layerPlan.layer
                )
            }
            guard seen.insert(layerPlan.layer).inserted else {
                throw BundleOwnedProductUpdatePlanningError
                    .duplicateLayer(layerPlan.layer)
            }
            if layerPlan.layer == .hostPlatform,
               index != specification.layerPlan.count - 1 {
                throw BundleOwnedProductUpdatePlanningError
                    .hostPlatformIsNotFinal
            }
            try validate(layerPlan)

            var dependencies = Set<UpdateLayer>()
            for dependency in layerPlan.dependsOn {
                guard dependencies.insert(dependency).inserted else {
                    throw BundleOwnedProductUpdatePlanningError
                        .duplicateDependency(
                            layer: layerPlan.layer,
                            dependency: dependency
                        )
                }
                guard seen.contains(dependency),
                      dependency != layerPlan.layer else {
                    throw BundleOwnedProductUpdatePlanningError
                        .dependencyIsNotEarlier(
                            layer: layerPlan.layer,
                            dependency: dependency
                        )
                }
            }
        }

        try requirePayloadClosureMatch(
            specification: specification,
            invocation: invocation
        )

        return ProductUpdateExecutionPlan(
            updateId: invocation.updateId,
            specificationId: specification.id,
            layerPlan: specification.layerPlan
        )
    }

    private static func requirePayloadClosureMatch(
        specification: ProductUpdateSpecification,
        invocation: UpdateBootstrapHandoffInvocation
    ) throws {
        let declared = UpdateBootstrapBundleClosurePolicy
            .declaredArtifacts(specification)
        let declaredByIdentifier = Dictionary(
            uniqueKeysWithValues: declared.map { ($0.id, $0) }
        )
        let closureByIdentifier = Dictionary(
            uniqueKeysWithValues: invocation.payloadArtifacts.map { ($0.id, $0) }
        )
        let declaredIds = Set(declaredByIdentifier.keys)
        let closureIds = Set(closureByIdentifier.keys)
        let missing = declaredIds.subtracting(closureIds).sorted()
        let unknown = closureIds.subtracting(declaredIds).sorted()
        guard missing.isEmpty, unknown.isEmpty else {
            throw BundleOwnedProductUpdatePlanningError
                .payloadClosureMismatch(missing: missing, unknown: unknown)
        }
        for id in declaredIds.sorted() {
            guard declaredByIdentifier[id] == closureByIdentifier[id] else {
                throw BundleOwnedProductUpdatePlanningError
                    .payloadClosureMismatch(missing: [], unknown: [id])
            }
        }
    }

    private static func validate(
        _ layerPlan: ProductUpdateLayerPlan
    ) throws {
        guard isArtifact(layerPlan.artifact) else {
            throw BundleOwnedProductUpdatePlanningError.invalidArtifact(
                layer: layerPlan.layer,
                role: "apply"
            )
        }
        let executor = layerPlan.effectExecutor
        guard isIdentifier(executor.id),
              isPayloadPath(executor.relativePath),
              isSHA256(executor.sha256),
              executor.sizeBytes > 0,
              executor.mediaType == effectExecutorMediaType,
              isArtifact(executor.configurationArtifact),
              executor.configurationArtifact.mediaType ==
                effectConfigurationMediaType else {
            throw BundleOwnedProductUpdatePlanningError
                .invalidEffectExecutor(layer: layerPlan.layer)
        }

        var identities = [
            layerPlan.artifact.id,
            executor.id,
            executor.configurationArtifact.id,
        ]
        var paths = [
            layerPlan.artifact.relativePath,
            executor.relativePath,
            executor.configurationArtifact.relativePath,
        ]
        var digests = [
            layerPlan.artifact.sha256,
            executor.sha256,
            executor.configurationArtifact.sha256,
        ]

        switch layerPlan.rollback.state {
        case .available:
            guard let artifact = layerPlan.rollback.artifact,
                  layerPlan.rollback.reason == nil,
                  isArtifact(artifact) else {
                throw BundleOwnedProductUpdatePlanningError
                    .invalidRollback(layer: layerPlan.layer)
            }
            identities.append(artifact.id)
            paths.append(artifact.relativePath)
            digests.append(artifact.sha256)
        case .unsupported:
            guard layerPlan.rollback.artifact == nil,
                  let reason = layerPlan.rollback.reason,
                  !reason.isEmpty else {
                throw BundleOwnedProductUpdatePlanningError
                    .invalidRollback(layer: layerPlan.layer)
            }
        }

        guard Set(identities).count == identities.count,
              Set(paths).count == paths.count,
              Set(digests).count == digests.count else {
            throw BundleOwnedProductUpdatePlanningError
                .conflictingArtifactIdentity(layer: layerPlan.layer)
        }
    }

    private static func isArtifact(_ artifact: UpdateBootstrapArtifact) -> Bool {
        isIdentifier(artifact.id)
            && isPayloadPath(artifact.relativePath)
            && isSHA256(artifact.sha256)
            && artifact.sizeBytes > 0
            && !artifact.mediaType.isEmpty
    }

    private static func isPayloadPath(_ path: String) -> Bool {
        path.hasPrefix("payload/")
            && path.count > "payload/".count
            && !path.contains("\\")
            && !path.split(separator: "/").contains("..")
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func isIdentifier(_ value: String) -> Bool {
        UpdateBootstrapIdentifierSyntax.isIdentifier(value)
    }
}
