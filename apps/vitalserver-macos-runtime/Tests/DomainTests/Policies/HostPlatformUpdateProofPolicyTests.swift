import Contracts
import Domain
import XCTest

final class HostPlatformUpdateProofPolicyTests: XCTestCase {
    func testAcceptsCompletedApplyCorrelatedToActiveInstallation() throws {
        let settlement = try completedSettlement()

        XCTAssertNoThrow(
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: [.completed],
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: targetRelease().sha256,
                operation: settlement.operation,
                installation: settlement.manifest
            )
        )
    }

    func testAcceptsRequestedFailureWhenPreviousReleaseIsUnchanged() throws {
        let failed = try failedAtRequested()

        XCTAssertNoThrow(
            try proveFailed(operation: failed, installation: try initialManifest())
        )
    }

    func testAcceptsPreparedFailureWhenPreviousReleaseIsUnchanged() throws {
        let failed = try failedBeforeIrreversibleEffect()

        XCTAssertNoThrow(
            try proveFailed(operation: failed, installation: try initialManifest())
        )
    }

    func testAcceptsCompensatedApplyWhenPreviousReleaseIsUnchanged() throws {
        let compensated = try compensatedOperation()

        XCTAssertNoThrow(
            try proveFailed(
                operation: compensated,
                installation: try initialManifest()
            )
        )
    }

    func testRejectsCompletedWhenFailedOrCompensatedWasRequired() throws {
        let settlement = try completedSettlement()

        XCTAssertThrowsError(
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: [.failed, .compensated],
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: targetRelease().sha256,
                operation: settlement.operation,
                installation: settlement.manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .phaseMismatch(
                    accepted: [.failed, .compensated],
                    actual: .completed
                )
            )
        }
    }

    func testRejectsPreparedPhaseWithoutInferringFromInstallation() throws {
        let prepared = try stagedOperation()

        XCTAssertThrowsError(
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: [.completed],
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: targetRelease().sha256,
                operation: prepared,
                installation: try initialManifest()
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .phaseMismatch(accepted: [.completed], actual: .prepared)
            )
        }
    }

    func testRejectsOperationIdentityMismatch() throws {
        let settlement = try completedSettlement()

        XCTAssertThrowsError(
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: [.completed],
                updateId: "update-99",
                apply: applyTransition(),
                applyArtifactSHA256: targetRelease().sha256,
                operation: settlement.operation,
                installation: settlement.manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .operationIdentityMismatch(
                    field: "id",
                    expected: "update-99.host-platform.apply",
                    actual: "update-42.host-platform.apply"
                )
            )
        }
    }

    func testRejectsCandidateSHAMismatch() throws {
        let settlement = try completedSettlement()

        XCTAssertThrowsError(
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: [.completed],
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: String(repeating: "f", count: 64),
                operation: settlement.operation,
                installation: settlement.manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .operationIdentityMismatch(
                    field: "targetRelease.sha256",
                    expected: String(repeating: "f", count: 64),
                    actual: targetRelease().sha256
                )
            )
        }
    }

    func testRejectsCompletedInstallationThatWasNotThisOperation() throws {
        let settlement = try completedSettlement()
        let otherInstall = try HostPlatformInstallationPolicy.makeInitialManifest(
            installationId: settlement.manifest.installationId,
            activeRelease: activeRelease(),
            operationId: "fresh-install.host-0.2.1",
            activatedAt: "2026-07-29T00:00:00Z"
        )

        XCTAssertThrowsError(
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: [.completed],
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: targetRelease().sha256,
                operation: settlement.operation,
                installation: otherInstall
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activationOperationId",
                    expected: settlement.operation.id,
                    actual: "fresh-install.host-0.2.1"
                )
            )
        }
    }

    func testRejectsFailedApplyWhoseActiveReleaseIdIsNotThePrevious() throws {
        let failed = try failedBeforeIrreversibleEffect()
        var other = activeRelease()
        other = HostPlatformRelease(
            id: "host-other",
            version: other.version,
            sha256: other.sha256,
            slotRelativePath: other.slotRelativePath
        )

        XCTAssertThrowsError(
            try proveFailed(
                operation: failed,
                installation: try installation(active: other)
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activeRelease.id",
                    expected: activeRelease().id,
                    actual: "host-other"
                )
            )
        }
    }

    func testRejectsFailedApplyWhoseActiveReleaseVersionIsNotThePrevious() throws {
        let failed = try failedBeforeIrreversibleEffect()
        var other = activeRelease()
        other = HostPlatformRelease(
            id: other.id,
            version: "0.1.9",
            sha256: other.sha256,
            slotRelativePath: other.slotRelativePath
        )

        XCTAssertThrowsError(
            try proveFailed(
                operation: failed,
                installation: try installation(active: other)
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activeRelease.version",
                    expected: activeRelease().version,
                    actual: "0.1.9"
                )
            )
        }
    }

    func testRejectsFailedApplyWhoseActiveReleaseDigestIsNotThePrevious() throws {
        let failed = try failedBeforeIrreversibleEffect()
        var other = activeRelease()
        other = HostPlatformRelease(
            id: other.id,
            version: other.version,
            sha256: String(repeating: "e", count: 64),
            slotRelativePath: other.slotRelativePath
        )

        XCTAssertThrowsError(
            try proveFailed(
                operation: failed,
                installation: try installation(active: other)
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activeRelease.sha256",
                    expected: activeRelease().sha256,
                    actual: String(repeating: "e", count: 64)
                )
            )
        }
    }

    func testRejectsFailedApplyWhoseActiveReleaseSlotIsNotThePrevious() throws {
        let failed = try failedBeforeIrreversibleEffect()
        var other = activeRelease()
        other = HostPlatformRelease(
            id: other.id,
            version: other.version,
            sha256: other.sha256,
            slotRelativePath: "releases/host-other"
        )

        XCTAssertThrowsError(
            try proveFailed(
                operation: failed,
                installation: try installation(active: other)
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activeRelease.slotRelativePath",
                    expected: activeRelease().slotRelativePath,
                    actual: "releases/host-other"
                )
            )
        }
    }

    func testRejectsFailedApplyWhenInstallationRevisionAdvanced() throws {
        let failed = try failedBeforeIrreversibleEffect()

        XCTAssertThrowsError(
            try proveFailed(
                operation: failed,
                installation: try installation(revision: 2)
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "installationRevision",
                    expected: "1",
                    actual: "2"
                )
            )
        }
    }

    func testRejectsCompensatedApplyWhenInstallationRevisionIsWrong() throws {
        let compensated = try compensatedOperation()

        XCTAssertThrowsError(
            try proveFailed(
                operation: compensated,
                installation: try installation(revision: 3)
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "installationRevision",
                    expected: "1",
                    actual: "3"
                )
            )
        }
    }

    func testRejectsFailedApplyThatNamesItselfAsActivationOwner() throws {
        let failed = try failedBeforeIrreversibleEffect()

        XCTAssertThrowsError(
            try proveFailed(
                operation: failed,
                installation: try installation(
                    activationOperationId: failed.id
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activationOperationId",
                    expected: "not \(failed.id)",
                    actual: failed.id
                )
            )
        }
    }

    func testRejectsCompensatedApplyThatNamesItselfAsActivationOwner() throws {
        let compensated = try compensatedOperation()

        XCTAssertThrowsError(
            try proveFailed(
                operation: compensated,
                installation: try installation(
                    activationOperationId: compensated.id
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activationOperationId",
                    expected: "not \(compensated.id)",
                    actual: compensated.id
                )
            )
        }
    }

    func testRejectsRequestedFailureWhenPreviousReleaseWasReplaced() throws {
        let failed = try failedAtRequested()

        XCTAssertThrowsError(
            try proveFailed(
                operation: failed,
                installation: try installation(active: targetRelease())
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activeRelease.id",
                    expected: activeRelease().id,
                    actual: targetRelease().id
                )
            )
        }
    }

    func testRejectsCompletedActiveReleaseVersionMismatch() throws {
        let settlement = try completedSettlement()
        let wrongVersion = HostPlatformRelease(
            id: settlement.manifest.activeRelease.id,
            version: "9.9.9",
            sha256: settlement.manifest.activeRelease.sha256,
            slotRelativePath: settlement.manifest.activeRelease.slotRelativePath
        )

        XCTAssertThrowsError(
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: [.completed],
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: targetRelease().sha256,
                operation: settlement.operation,
                installation: HostPlatformInstallationManifest(
                    schemaVersion: settlement.manifest.schemaVersion,
                    installationId: settlement.manifest.installationId,
                    installationRevision: settlement.manifest.installationRevision,
                    activeRelease: wrongVersion,
                    rollbackRelease: settlement.manifest.rollbackRelease,
                    activationOperationId: settlement.manifest.activationOperationId,
                    activatedAt: settlement.manifest.activatedAt
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activeRelease.version",
                    expected: targetRelease().version,
                    actual: "9.9.9"
                )
            )
        }
    }

    func testRejectsCompletedActiveReleaseSlotMismatch() throws {
        let settlement = try completedSettlement()
        let wrongSlot = HostPlatformRelease(
            id: settlement.manifest.activeRelease.id,
            version: settlement.manifest.activeRelease.version,
            sha256: settlement.manifest.activeRelease.sha256,
            slotRelativePath: "releases/wrong"
        )

        XCTAssertThrowsError(
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: [.completed],
                updateId: "update-42",
                apply: applyTransition(),
                applyArtifactSHA256: targetRelease().sha256,
                operation: settlement.operation,
                installation: HostPlatformInstallationManifest(
                    schemaVersion: settlement.manifest.schemaVersion,
                    installationId: settlement.manifest.installationId,
                    installationRevision: settlement.manifest.installationRevision,
                    activeRelease: wrongSlot,
                    rollbackRelease: settlement.manifest.rollbackRelease,
                    activationOperationId: settlement.manifest.activationOperationId,
                    activatedAt: settlement.manifest.activatedAt
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformUpdateProofPolicyError,
                .installationIdentityMismatch(
                    field: "activeRelease.slotRelativePath",
                    expected: targetRelease().slotRelativePath,
                    actual: "releases/wrong"
                )
            )
        }
    }

    func testExpectedApplyOperationIdUsesHostPlatformOwnerIdentity() {
        XCTAssertEqual(
            HostPlatformUpdateProofPolicy.expectedApplyOperationId(
                updateId: "update-42"
            ),
            "update-42.host-platform.apply"
        )
    }
}

extension HostPlatformUpdateProofPolicyTests {
    fileprivate func applyTransition() -> HostPlatformLayerTransition {
        HostPlatformLayerTransition(
            installationId: "installation-1",
            expectedInstallationRevision: 1,
            targetReleaseId: targetRelease().id,
            targetReleaseVersion: targetRelease().version,
            targetSlotRelativePath: targetRelease().slotRelativePath
        )
    }

    fileprivate func completedSettlement() throws -> (
        operation: HostPlatformInstallationOperation,
        manifest: HostPlatformInstallationManifest
    ) {
        let loaded = try HostPlatformInstallationPolicy.recordLoadTargetServices(
            operation: try HostPlatformInstallationPolicy.recordActivateTarget(
                operation: try publishedOperation(),
                resolvedTarget: "/install/releases/host-0.2.2/release",
                updatedAt: "2026-07-29T01:00:04Z"
            ),
            observations: [],
            updatedAt: "2026-07-29T01:00:05Z"
        )
        return try HostPlatformInstallationPolicy.makeCompletedSettlement(
            operation: loaded,
            settledAt: "2026-07-29T01:00:06Z"
        )
    }

    fileprivate func proveFailed(
        operation: HostPlatformInstallationOperation,
        installation: HostPlatformInstallationManifest
    ) throws {
        try HostPlatformUpdateProofPolicy.prove(
            acceptedPhases: [.failed, .compensated],
            updateId: "update-42",
            apply: applyTransition(),
            applyArtifactSHA256: targetRelease().sha256,
            operation: operation,
            installation: installation
        )
    }

    fileprivate func installation(
        revision: Int? = nil,
        active: HostPlatformRelease? = nil,
        activationOperationId: String? = nil
    ) throws -> HostPlatformInstallationManifest {
        let base = try initialManifest()
        return HostPlatformInstallationManifest(
            schemaVersion: base.schemaVersion,
            installationId: base.installationId,
            installationRevision: revision ?? base.installationRevision,
            activeRelease: active ?? base.activeRelease,
            rollbackRelease: base.rollbackRelease,
            activationOperationId:
                activationOperationId ?? base.activationOperationId,
            activatedAt: base.activatedAt
        )
    }

    fileprivate func failedAtRequested() throws -> HostPlatformInstallationOperation {
        try HostPlatformInstallationPolicy.recordFailure(
            operation: try requestedOperation(),
            reason: "candidate staging failed",
            updatedAt: "2026-07-29T01:00:01Z"
        )
    }

    fileprivate func failedBeforeIrreversibleEffect() throws
        -> HostPlatformInstallationOperation
    {
        try HostPlatformInstallationPolicy.recordFailure(
            operation: try stagedOperation(),
            reason: "topology mismatch",
            updatedAt: "2026-07-29T01:00:02Z"
        )
    }

    fileprivate func compensatedOperation() throws -> HostPlatformInstallationOperation {
        let compensating = try HostPlatformInstallationPolicy.recordCompensating(
            operation: try publishedOperation(),
            reason: "target service load failed",
            updatedAt: "2026-07-29T01:00:04Z"
        )
        return try HostPlatformInstallationPolicy.recordCompensated(
            operation: compensating,
            updatedAt: "2026-07-29T01:00:05Z"
        )
    }

    fileprivate func publishedOperation() throws -> HostPlatformInstallationOperation {
        let quiesced = try HostPlatformInstallationPolicy.recordQuiescePrevious(
            operation: try stagedOperation(),
            observations: [],
            updatedAt: "2026-07-29T01:00:02Z"
        )
        return try HostPlatformInstallationPolicy.recordPublishInterfaces(
            operation: quiesced,
            updatedAt: "2026-07-29T01:00:03Z"
        )
    }

    fileprivate func stagedOperation() throws -> HostPlatformInstallationOperation {
        try HostPlatformInstallationPolicy.recordStagedCandidate(
            operation: try requestedOperation(),
            candidate: HostPlatformStagedCandidate(
                release: targetRelease(),
                stagingReceiptId: "update-42.candidate",
                stagedAt: "2026-07-29T01:00:01Z"
            ),
            updatedAt: "2026-07-29T01:00:01Z"
        )
    }

    fileprivate func requestedOperation() throws -> HostPlatformInstallationOperation {
        try HostPlatformInstallationPolicy.makeRequestedOperation(
            command: HostPlatformInstallationCommand(
                operationId: "update-42.host-platform.apply",
                kind: .apply,
                installationId: "installation-1",
                expectedInstallationRevision: 1,
                targetRelease: targetRelease(),
                sourceArtifactPath: "/incoming/host-platform.pkg",
                sourceArtifactSizeBytes: 1024,
                sourceArtifactMediaType:
                    HostPlatformReleaseArchiveContract.mediaType,
                stagingAttemptId: "update-42.apply",
                requestedAt: "2026-07-29T01:00:00Z"
            ),
            activeManifest: try initialManifest()
        )
    }

    fileprivate func initialManifest() throws -> HostPlatformInstallationManifest {
        try HostPlatformInstallationPolicy.makeInitialManifest(
            installationId: "installation-1",
            activeRelease: activeRelease(),
            operationId: "fresh-install.host-0.2.1",
            activatedAt: "2026-07-29T00:00:00Z"
        )
    }

    fileprivate func activeRelease() -> HostPlatformRelease {
        HostPlatformRelease(
            id: "host-0.2.1",
            version: "0.2.1",
            sha256: String(repeating: "a", count: 64),
            slotRelativePath: "releases/host-0.2.1"
        )
    }

    fileprivate func targetRelease() -> HostPlatformRelease {
        HostPlatformRelease(
            id: "host-0.2.2",
            version: "0.2.2",
            sha256: String(repeating: "b", count: 64),
            slotRelativePath: "releases/host-0.2.2"
        )
    }
}
