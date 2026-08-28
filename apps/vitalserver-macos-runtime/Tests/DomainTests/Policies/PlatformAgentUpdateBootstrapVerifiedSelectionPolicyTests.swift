import Contracts
import Domain
import XCTest

final class PlatformAgentUpdateBootstrapVerifiedSelectionPolicyTests:
    XCTestCase
{
    func testRecordedSelectionIsVerifiedWithoutABoundRequest() throws {
        let selection = PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .verified(
                selectionId: selectionId,
                verificationInvocationId: invocationId,
                updateId: "update-42",
                canonicalPayloadSHA256: digest,
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:00Z"
            )

        try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.validate(
            selection
        )
        XCTAssertEqual(
            selection.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateVerified
        )
        XCTAssertNil(selection.boundRequestId)
        XCTAssertNil(selection.journalCorrelation)
    }

    func testReselectReplacesVerifiedAndSpentButNotCommitted() throws {
        let first = verified()
        let second = PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.verified(
            selectionId: "22222222-3333-4444-5555-666666666666",
            verificationInvocationId: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff",
            updateId: "update-43",
            canonicalPayloadSHA256: String(repeating: "cd", count: 32),
            observedBundlePath: "/tmp/other.tar.gz",
            observedAt: "2026-08-24T00:01:00Z"
        )

        XCTAssertEqual(
            try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.replace(
                current: first,
                with: second
            ).selectionId,
            second.selectionId
        )
        let committed = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .commitApply(
                selection: first,
                requestId: "request-1",
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:01Z"
            ).selection
        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.replace(
                current: committed,
                with: second
            )
        ) { error in
            XCTAssertEqual(
                error as? PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError,
                .inFlight(requestId: "request-1")
            )
        }
        let spent = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .spend(
                selection: committed,
                requestId: "request-1",
                observedAt: "2026-08-24T00:00:02Z"
            ).selection
        XCTAssertEqual(
            try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.replace(
                current: spent,
                with: second
            ).selectionId,
            second.selectionId
        )
    }

    func testCommitApplyIsSingleDocumentAndResumeIsIdempotent() throws {
        let committed = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .commitApply(
                selection: verified(),
                requestId: "request-1",
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:01Z"
            )

        XCTAssertTrue(committed.persisted)
        XCTAssertEqual(
            committed.selection.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .stateApplyCommitted
        )
        XCTAssertEqual(committed.selection.boundRequestId, "request-1")
        XCTAssertEqual(
            committed.selection.journalCorrelation?.verificationInvocationId,
            invocationId
        )

        let resumed = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .commitApply(
                selection: committed.selection,
                requestId: "request-1",
                observedBundlePath: "/tmp/other.tar.gz",
                observedAt: "2026-08-24T00:00:02Z"
            )
        XCTAssertFalse(resumed.persisted)
        XCTAssertEqual(resumed.selection.boundRequestId, "request-1")
    }

    func testCommitApplyOfDifferentRequestIdOnCommittedIsStale() {
        let committed = try! PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .commitApply(
                selection: verified(),
                requestId: "request-1",
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:01Z"
            )

        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.commitApply(
                selection: committed.selection,
                requestId: "request-2",
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:02Z"
            )
        ) { error in
            XCTAssertEqual(
                error as? PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError,
                .stale
            )
        }
    }

    func testCommitApplyPathMismatchIsObservationConflictNotIdentity() {
        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.commitApply(
                selection: verified(),
                requestId: "request-1",
                observedBundlePath: "/tmp/other.tar.gz",
                observedAt: "2026-08-24T00:00:01Z"
            )
        ) { error in
            XCTAssertEqual(
                error as? PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError,
                .conflict(
                    expectedPath: "/tmp/update.tar.gz",
                    actualPath: "/tmp/other.tar.gz"
                )
            )
        }
    }

    func testSpendMakesSelectionUnreusableExceptSameRequestIdIdempotency() throws {
        let committed = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .commitApply(
                selection: verified(),
                requestId: "request-1",
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:01Z"
            ).selection
        let spent = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .spend(
                selection: committed,
                requestId: "request-1",
                observedAt: "2026-08-24T00:00:02Z"
            )

        XCTAssertTrue(spent.persisted)
        XCTAssertEqual(
            spent.selection.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateSpent
        )
        let again = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .spend(
                selection: spent.selection,
                requestId: "request-1",
                observedAt: "2026-08-24T00:00:03Z"
            )
        XCTAssertFalse(again.persisted)
        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.commitApply(
                selection: spent.selection,
                requestId: "request-2",
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:04Z"
            )
        ) { error in
            XCTAssertEqual(
                error as? PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError,
                .stale
            )
        }
    }

    func testProofTreatsMissingJournalCorrelationAsMissingNotSuccess() {
        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapApplySelectionProofPolicy.prove(
                journalCorrelation: nil,
                expectedVerificationInvocationId: invocationId,
                expectedUpdateId: "update-42",
                expectedCanonicalPayloadSHA256: digest
            )
        ) { error in
            XCTAssertEqual(
                error as? PlatformAgentUpdateBootstrapApplySelectionProofPolicyError,
                .missing
            )
        }
    }

    func testProofCorrelatesJournalSelectionToVerificationIdentities() throws {
        let correlation = UpdateBootstrapPlatformAgentSelectionCorrelation(
            selectionId: selectionId,
            verificationInvocationId: invocationId,
            updateId: "update-42",
            canonicalPayloadSHA256: digest
        )

        let proven = try
            PlatformAgentUpdateBootstrapApplySelectionProofPolicy.prove(
                journalCorrelation: correlation,
                expectedVerificationInvocationId: invocationId,
                expectedUpdateId: "update-42",
                expectedCanonicalPayloadSHA256: digest
            )

        XCTAssertEqual(proven.selectionId, selectionId)
    }

    func testProofKeepsDigestMismatchDistinctFromMissing() {
        let correlation = UpdateBootstrapPlatformAgentSelectionCorrelation(
            selectionId: selectionId,
            verificationInvocationId: invocationId,
            updateId: "update-42",
            canonicalPayloadSHA256: digest
        )
        let other = String(repeating: "cd", count: 32)

        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapApplySelectionProofPolicy.prove(
                journalCorrelation: correlation,
                expectedVerificationInvocationId: invocationId,
                expectedUpdateId: "update-42",
                expectedCanonicalPayloadSHA256: other
            )
        ) { error in
            XCTAssertEqual(
                error as? PlatformAgentUpdateBootstrapApplySelectionProofPolicyError,
                .identityMismatch(
                    field: "canonicalPayloadSHA256",
                    expected: other,
                    actual: digest
                )
            )
        }
    }

    private func verified() -> PlatformAgentUpdateBootstrapVerifiedSelection {
        PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.verified(
            selectionId: selectionId,
            verificationInvocationId: invocationId,
            updateId: "update-42",
            canonicalPayloadSHA256: digest,
            observedBundlePath: "/tmp/update.tar.gz",
            observedAt: "2026-08-24T00:00:00Z"
        )
    }

    private var selectionId: String {
        "11111111-2222-3333-4444-555555555555"
    }

    private var invocationId: String {
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }

    private var digest: String {
        String(repeating: "ab", count: 32)
    }
}
