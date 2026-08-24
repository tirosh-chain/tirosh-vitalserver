import Contracts

public enum HostPlatformLayerEffectPolicyError: Error, Equatable, Sendable {
    case invalidInvocation
    case invalidConfiguration
    case executorIdentityMismatch
    case unsupportedLayer
    case operationMismatch
    case artifactDigestMismatch
    case ownerOperationMismatch
    case ownerOperationNotSucceeded(HostPlatformInstallationPhase)
}

public enum HostPlatformLayerEffectPolicy {
    public static let configurationSchemaVersion =
        "vitalserver.host-platform-layer-effect-configuration/v1"

    public static func makeManagerCommand(
        invocation: ProductUpdateLayerEffectInvocation,
        configuration: HostPlatformLayerEffectConfiguration,
        requestedAt: String
    ) throws -> HostPlatformInstallationCommand {
        try validate(invocation: invocation, configuration: configuration)
        let transition =
            invocation.operation == .apply
            ? configuration.apply : configuration.rollback
        return HostPlatformInstallationCommand(
            operationId:
                "\(invocation.updateId).host-platform.\(invocation.operation.rawValue)",
            kind:
                invocation.operation == .apply
                ? .apply : .rollback,
            installationId: transition.installationId,
            expectedInstallationRevision:
                transition.expectedInstallationRevision,
            targetRelease: HostPlatformRelease(
                id: transition.targetReleaseId,
                version: transition.targetReleaseVersion,
                sha256: invocation.artifactSHA256,
                slotRelativePath: transition.targetSlotRelativePath
            ),
            sourceArtifactPath: invocation.artifactPath,
            sourceArtifactSizeBytes: UInt64(invocation.artifactSizeBytes),
            sourceArtifactMediaType: invocation.artifactMediaType,
            stagingAttemptId:
                "\(invocation.updateId).\(invocation.operation.rawValue)",
            requestedAt: requestedAt
        )
    }

    public static func makeLayerReceipt(
        invocation: ProductUpdateLayerEffectInvocation,
        operation: HostPlatformInstallationOperation
    ) throws -> ProductUpdateLayerEffectReceipt {
        let expectedOperationId =
            "\(invocation.updateId).host-platform.\(invocation.operation.rawValue)"
        guard operation.id == expectedOperationId,
            operation.kind
                == (invocation.operation == .apply ? .apply : .rollback),
            operation.targetRelease.sha256 == invocation.artifactSHA256
        else {
            throw HostPlatformLayerEffectPolicyError.ownerOperationMismatch
        }
        guard operation.phase == .completed else {
            throw HostPlatformLayerEffectPolicyError
                .ownerOperationNotSucceeded(operation.phase)
        }
        return ProductUpdateLayerEffectReceipt(
            schemaVersion: ProductUpdateExecutionContract.schemaVersion,
            updateId: invocation.updateId,
            layer: .hostPlatform,
            effectExecutorId: invocation.effectExecutorId,
            operation: invocation.operation,
            artifactSHA256: invocation.artifactSHA256,
            state: .succeeded,
            observedAt: operation.updatedAt,
            evidence: ProductUpdateEvidenceReference(
                kind: "host-platform-installation-operation",
                id: operation.id
            ),
            issue: nil
        )
    }

    public static func validate(
        invocation: ProductUpdateLayerEffectInvocation,
        configuration: HostPlatformLayerEffectConfiguration
    ) throws {
        guard invocation.schemaVersion
                == ProductUpdateExecutionContract
                .layerEffectInvocationSchemaVersion,
            !invocation.updateId.isEmpty,
            invocation.artifactPath.hasPrefix("/"),
            invocation.configurationPath.hasPrefix("/"),
            invocation.artifactSHA256.count == 64,
            invocation.artifactSizeBytes > 0,
            invocation.artifactMediaType
                == HostPlatformReleaseArchiveContract.mediaType
        else {
            throw HostPlatformLayerEffectPolicyError.invalidInvocation
        }
        guard invocation.layer == .hostPlatform else {
            throw HostPlatformLayerEffectPolicyError.unsupportedLayer
        }
        guard configuration.schemaVersion == configurationSchemaVersion,
            configuration.manager.executablePath.hasPrefix("/"),
            configuration.manager.databasePath.hasPrefix("/"),
            configuration.manager.installationRootPath.hasPrefix("/"),
            configuration.manager.launchctlExecutablePath.hasPrefix("/"),
            configuration.manager.exchangeRootPath.hasPrefix("/"),
            configuration.apply.expectedInstallationRevision > 0,
            configuration.rollback.expectedInstallationRevision
                == configuration.apply.expectedInstallationRevision + 1
        else {
            throw HostPlatformLayerEffectPolicyError.invalidConfiguration
        }
        guard invocation.effectExecutorId == configuration.effectExecutorId else {
            throw HostPlatformLayerEffectPolicyError.executorIdentityMismatch
        }
        guard configuration.rollback.installationId
                == configuration.apply.installationId,
            configuration.apply.targetReleaseId
                != configuration.rollback.targetReleaseId
        else {
            throw HostPlatformLayerEffectPolicyError.invalidConfiguration
        }
    }
}
