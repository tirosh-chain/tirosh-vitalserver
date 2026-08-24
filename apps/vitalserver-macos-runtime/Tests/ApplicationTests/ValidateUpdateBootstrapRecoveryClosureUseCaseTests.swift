import Application
import Contracts
import XCTest

final class ValidateUpdateBootstrapRecoveryClosureUseCaseTests:
    XCTestCase
{
    func testAcceptsExactStagedClosureOwnedByJournal() throws {
        let journal = recoveryJournal(state: .handoffPending)

        XCTAssertNoThrow(
            try ValidateUpdateBootstrapRecoveryClosureUseCase().validate(
                journal: journal,
                stagedEnvelope: journal.envelope,
                verification: verification(for: journal)
            )
        )
    }

    func testRejectsDifferentStagedEnvelope() {
        let journal = recoveryJournal(state: .handoffPending)
        let different = UpdateBootstrapEnvelope(
            schemaVersion: journal.envelope.schemaVersion,
            id: journal.envelope.id,
            productId: journal.envelope.productId,
            target: journal.envelope.target,
            targetRelease: UpdateBootstrapRelease(
                productVersion: "0.2.3",
                runtimeVersion: "0.2.3"
            ),
            layerOrder: journal.envelope.layerOrder,
            nextUpdaterArtifact: journal.envelope.nextUpdaterArtifact,
            specification: journal.envelope.specification,
            payloadArtifacts: journal.envelope.payloadArtifacts,
            signature: journal.envelope.signature,
            issuedAt: journal.envelope.issuedAt
        )

        XCTAssertThrowsError(
            try ValidateUpdateBootstrapRecoveryClosureUseCase().validate(
                journal: journal,
                stagedEnvelope: different,
                verification: verification(for: journal)
            )
        ) { error in
            XCTAssertEqual(
                error as? ValidateUpdateBootstrapRecoveryClosureError,
                .envelopeMismatch
            )
        }
    }

    func testRejectsVerificationDigestThatDiffersFromJournal() {
        let journal = recoveryJournal(state: .handoffPending)

        XCTAssertThrowsError(
            try ValidateUpdateBootstrapRecoveryClosureUseCase().validate(
                journal: journal,
                stagedEnvelope: journal.envelope,
                verification: VerifiedUpdateBootstrapClosure(
                    updateId: journal.envelope.id,
                    canonicalPayloadSHA256: String(repeating: "d", count: 64),
                    verifiedBootstrapArtifactIds: [
                        journal.envelope.nextUpdaterArtifact.id,
                        journal.envelope.specification.id,
                    ],
                    verifiedPayloadArtifactIds:
                        journal.envelope.payloadArtifacts.map(\.id)
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ValidateUpdateBootstrapRecoveryClosureError,
                .verificationDigestMismatch(
                    expected: journal.bootstrapSignedSHA256,
                    actual: String(repeating: "d", count: 64)
                )
            )
        }
    }

    func testRejectsMissingPayloadProof() {
        let journal = recoveryJournal(state: .handoffPending)

        XCTAssertThrowsError(
            try ValidateUpdateBootstrapRecoveryClosureUseCase().validate(
                journal: journal,
                stagedEnvelope: journal.envelope,
                verification: VerifiedUpdateBootstrapClosure(
                    updateId: journal.envelope.id,
                    canonicalPayloadSHA256: journal.bootstrapSignedSHA256,
                    verifiedBootstrapArtifactIds: [
                        journal.envelope.nextUpdaterArtifact.id,
                        journal.envelope.specification.id,
                    ],
                    verifiedPayloadArtifactIds: []
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ValidateUpdateBootstrapRecoveryClosureError,
                .verifiedPayloadArtifactSetMismatch(
                    expected:
                        journal.envelope.payloadArtifacts.map(\.id).sorted(),
                    actual: []
                )
            )
        }
    }

    func testRejectsExtraPayloadProof() {
        let journal = recoveryJournal(state: .handoffPending)

        XCTAssertThrowsError(
            try ValidateUpdateBootstrapRecoveryClosureUseCase().validate(
                journal: journal,
                stagedEnvelope: journal.envelope,
                verification: VerifiedUpdateBootstrapClosure(
                    updateId: journal.envelope.id,
                    canonicalPayloadSHA256: journal.bootstrapSignedSHA256,
                    verifiedBootstrapArtifactIds: [
                        journal.envelope.nextUpdaterArtifact.id,
                        journal.envelope.specification.id,
                    ],
                    verifiedPayloadArtifactIds:
                        journal.envelope.payloadArtifacts.map(\.id)
                        + ["extra-artifact"]
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? ValidateUpdateBootstrapRecoveryClosureError,
                .verifiedPayloadArtifactSetMismatch(
                    expected:
                        journal.envelope.payloadArtifacts.map(\.id).sorted(),
                    actual: (
                        journal.envelope.payloadArtifacts.map(\.id)
                        + ["extra-artifact"]
                    ).sorted()
                )
            )
        }
    }

    private func verification(
        for journal: UpdateBootstrapJournal
    ) -> VerifiedUpdateBootstrapClosure {
        VerifiedUpdateBootstrapClosure(
            updateId: journal.envelope.id,
            canonicalPayloadSHA256: journal.bootstrapSignedSHA256,
            verifiedBootstrapArtifactIds: [
                journal.envelope.nextUpdaterArtifact.id,
                journal.envelope.specification.id,
            ],
            verifiedPayloadArtifactIds:
                journal.envelope.payloadArtifacts.map(\.id)
        )
    }
}
