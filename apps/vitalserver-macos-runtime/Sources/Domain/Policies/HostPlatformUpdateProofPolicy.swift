import Contracts

public enum HostPlatformUpdateProofPolicyError: Error, Equatable, Sendable {
    case operationIdentityMismatch(
        field: String,
        expected: String,
        actual: String
    )
    case phaseMismatch(
        accepted: [HostPlatformInstallationPhase],
        actual: HostPlatformInstallationPhase
    )
    case installationIdentityMismatch(
        field: String,
        expected: String,
        actual: String
    )
}

public enum HostPlatformUpdateProofPolicy {
    public static func expectedApplyOperationId(updateId: String) -> String {
        "\(updateId).host-platform.apply"
    }

    public static func prove(
        acceptedPhases: [HostPlatformInstallationPhase],
        updateId: String,
        apply: HostPlatformLayerTransition,
        applyArtifactSHA256: String,
        operation: HostPlatformInstallationOperation,
        installation: HostPlatformInstallationManifest
    ) throws {
        let expectedOperationId = expectedApplyOperationId(updateId: updateId)
        try requireEqual(
            field: "id",
            expected: expectedOperationId,
            actual: operation.id
        )
        try requireEqual(
            field: "kind",
            expected: HostPlatformInstallationOperationKind.apply.rawValue,
            actual: operation.kind.rawValue
        )
        try requireEqual(
            field: "installationId",
            expected: apply.installationId,
            actual: operation.installationId
        )
        try requireEqual(
            field: "expectedInstallationRevision",
            expected: String(apply.expectedInstallationRevision),
            actual: String(operation.expectedInstallationRevision)
        )
        try requireEqual(
            field: "targetRelease.id",
            expected: apply.targetReleaseId,
            actual: operation.targetRelease.id
        )
        try requireEqual(
            field: "targetRelease.version",
            expected: apply.targetReleaseVersion,
            actual: operation.targetRelease.version
        )
        try requireEqual(
            field: "targetRelease.slotRelativePath",
            expected: apply.targetSlotRelativePath,
            actual: operation.targetRelease.slotRelativePath
        )
        try requireEqual(
            field: "targetRelease.sha256",
            expected: applyArtifactSHA256,
            actual: operation.targetRelease.sha256
        )
        if let candidate = operation.candidate {
            try requireEqual(
                field: "candidate.release.id",
                expected: operation.targetRelease.id,
                actual: candidate.release.id
            )
            try requireEqual(
                field: "candidate.release.sha256",
                expected: operation.targetRelease.sha256,
                actual: candidate.release.sha256
            )
        }

        guard acceptedPhases.contains(operation.phase) else {
            throw HostPlatformUpdateProofPolicyError.phaseMismatch(
                accepted: acceptedPhases,
                actual: operation.phase
            )
        }

        try requireInstallationEqual(
            field: "installationId",
            expected: operation.installationId,
            actual: installation.installationId
        )
        switch operation.phase {
        case .completed:
            try requireInstallationEqual(
                field: "activationOperationId",
                expected: operation.id,
                actual: installation.activationOperationId
            )
            try requireRelease(
                fieldPrefix: "activeRelease",
                expected: operation.targetRelease,
                actual: installation.activeRelease
            )
            try requireInstallationEqual(
                field: "installationRevision",
                expected: String(operation.expectedInstallationRevision + 1),
                actual: String(installation.installationRevision)
            )
        case .failed, .compensated:
            try requireRelease(
                fieldPrefix: "activeRelease",
                expected: operation.previousRelease,
                actual: installation.activeRelease
            )
            try requireInstallationEqual(
                field: "installationRevision",
                expected: String(operation.expectedInstallationRevision),
                actual: String(installation.installationRevision)
            )
            guard installation.activationOperationId != operation.id else {
                throw HostPlatformUpdateProofPolicyError
                    .installationIdentityMismatch(
                        field: "activationOperationId",
                        expected: "not \(operation.id)",
                        actual: installation.activationOperationId
                    )
            }
        case .requested, .prepared, .previousQuiesced, .interfacesPublished,
            .targetActivated, .targetServicesLoaded, .compensating:
            throw HostPlatformUpdateProofPolicyError.phaseMismatch(
                accepted: acceptedPhases,
                actual: operation.phase
            )
        }
    }

    private static func requireEqual(
        field: String,
        expected: String,
        actual: String
    ) throws {
        guard expected == actual else {
            throw HostPlatformUpdateProofPolicyError.operationIdentityMismatch(
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }

    private static func requireInstallationEqual(
        field: String,
        expected: String,
        actual: String
    ) throws {
        guard expected == actual else {
            throw HostPlatformUpdateProofPolicyError
                .installationIdentityMismatch(
                    field: field,
                    expected: expected,
                    actual: actual
                )
        }
    }

    private static func requireRelease(
        fieldPrefix: String,
        expected: HostPlatformRelease,
        actual: HostPlatformRelease
    ) throws {
        try requireInstallationEqual(
            field: "\(fieldPrefix).id",
            expected: expected.id,
            actual: actual.id
        )
        try requireInstallationEqual(
            field: "\(fieldPrefix).version",
            expected: expected.version,
            actual: actual.version
        )
        try requireInstallationEqual(
            field: "\(fieldPrefix).sha256",
            expected: expected.sha256,
            actual: actual.sha256
        )
        try requireInstallationEqual(
            field: "\(fieldPrefix).slotRelativePath",
            expected: expected.slotRelativePath,
            actual: actual.slotRelativePath
        )
    }
}
