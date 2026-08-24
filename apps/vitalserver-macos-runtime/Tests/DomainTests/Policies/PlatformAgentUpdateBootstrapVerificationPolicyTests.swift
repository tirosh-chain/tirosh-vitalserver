import Contracts
import Domain
import XCTest

final class PlatformAgentUpdateBootstrapVerificationPolicyTests: XCTestCase {
    func testOutcomeMapsSpawnFailureWithoutReadingABinding() {
        let outcome = PlatformAgentUpdateBootstrapVerificationPolicy.outcome(
            spawn: .spawnFailed(reason: "launcher missing"),
            expectedVerificationInvocationId: invocationId,
            bindingRead: .missing(path: "/tmp/binding.json")
        )

        XCTAssertEqual(outcome, .spawnFailed(reason: "launcher missing"))
    }

    func testOutcomeMapsNonzeroExitWithoutTreatingItAsSpawnFailure() {
        let outcome = PlatformAgentUpdateBootstrapVerificationPolicy.outcome(
            spawn: .completed(exitCode: 2),
            expectedVerificationInvocationId: invocationId,
            bindingRead: .loaded(binding())
        )

        XCTAssertEqual(outcome, .commandFailed(exitCode: 2))
    }

    func testOutcomeMapsEachBindingReadKindWithoutCollapsing() {
        let cases: [(
            UpdateBootstrapVerificationInvocationBindingReadInput,
            PlatformAgentUpdateBootstrapVerificationOutcome
        )] = [
            (
                .missing(path: "/tmp/binding.json"),
                .bindingMissing(path: "/tmp/binding.json")
            ),
            (
                .inspectionFailed(path: "/tmp/binding.json", reason: "stat failed"),
                .bindingInspectionFailed(
                    path: "/tmp/binding.json",
                    reason: "stat failed"
                )
            ),
            (
                .permissionDenied(path: "/tmp/binding.json", reason: "EACCES"),
                .bindingPermissionDenied(
                    path: "/tmp/binding.json",
                    reason: "EACCES"
                )
            ),
            (
                .readFailed(path: "/tmp/binding.json", reason: "EIO"),
                .bindingReadFailed(path: "/tmp/binding.json", reason: "EIO")
            ),
            (
                .decodeFailed(path: "/tmp/binding.json", reason: "not json"),
                .bindingDecodeFailed(
                    path: "/tmp/binding.json",
                    reason: "not json"
                )
            ),
            (
                .unexpectedPathState(path: "/tmp/binding.json", state: "directory"),
                .bindingUnexpectedPathState(
                    path: "/tmp/binding.json",
                    state: "directory"
                )
            ),
        ]
        for (bindingRead, expected) in cases {
            XCTAssertEqual(
                PlatformAgentUpdateBootstrapVerificationPolicy.outcome(
                    spawn: .completed(exitCode: 0),
                    expectedVerificationInvocationId: invocationId,
                    bindingRead: bindingRead
                ),
                expected
            )
        }
    }

    func testOutcomeSucceedsWhenBindingMatchesInvocationId() {
        let outcome = PlatformAgentUpdateBootstrapVerificationPolicy.outcome(
            spawn: .completed(exitCode: 0),
            expectedVerificationInvocationId: invocationId,
            bindingRead: .loaded(binding())
        )

        XCTAssertEqual(
            outcome,
            .succeeded(
                updateId: "update-42",
                canonicalPayloadSHA256: digest
            )
        )
    }

    func testOutcomeMapsUnrelatedBindingAsIdentityMismatch() {
        let outcome = PlatformAgentUpdateBootstrapVerificationPolicy.outcome(
            spawn: .completed(exitCode: 0),
            expectedVerificationInvocationId: "other-invocation",
            bindingRead: .loaded(binding())
        )

        XCTAssertEqual(
            outcome,
            .bindingIdentityMismatch(
                field: "verificationInvocationId",
                expected: "other-invocation",
                actual: invocationId
            )
        )
    }

    func testEvidenceFieldShapeIsExactForEachTerminalKind() throws {
        let invoked = PlatformAgentUpdateBootstrapVerificationPolicy.invoked(
            verificationInvocationId: invocationId,
            bundlePath: "/tmp/update.tar.gz",
            observedAt: "2026-08-24T00:00:00Z"
        )
        let outcomes: [PlatformAgentUpdateBootstrapVerificationOutcome] = [
            .spawnFailed(reason: "launcher missing"),
            .commandFailed(exitCode: 2),
            .bindingMissing(path: "/tmp/binding.json"),
            .bindingInspectionFailed(
                path: "/tmp/binding.json",
                reason: "stat failed"
            ),
            .bindingPermissionDenied(
                path: "/tmp/binding.json",
                reason: "EACCES"
            ),
            .bindingReadFailed(path: "/tmp/binding.json", reason: "EIO"),
            .bindingDecodeFailed(path: "/tmp/binding.json", reason: "not json"),
            .bindingUnexpectedPathState(
                path: "/tmp/binding.json",
                state: "directory"
            ),
            .bindingInvalid(reason: "unsupportedSchemaVersion"),
            .bindingIdentityMismatch(
                field: "verificationInvocationId",
                expected: "other",
                actual: invocationId
            ),
            .succeeded(updateId: "update-42", canonicalPayloadSHA256: digest),
        ]
        for outcome in outcomes {
            let evidence = PlatformAgentUpdateBootstrapVerificationPolicy
                .evidence(from: invoked, outcome: outcome)
            XCTAssertNoThrow(
                try PlatformAgentUpdateBootstrapVerificationPolicy.validate(
                    evidence
                )
            )
        }
        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapVerificationPolicy.validate(
                PlatformAgentUpdateBootstrapVerificationPolicy.evidence(
                    from: invoked,
                    outcome: .bindingMissing(path: "/tmp/binding.json")
                ).adding(spawnFailureReason: "hidden")
            )
        )
    }

    func testProofSurfacesEachTerminalKindDistinctly() {
        let invoked = PlatformAgentUpdateBootstrapVerificationPolicy.invoked(
            verificationInvocationId: invocationId,
            bundlePath: "/tmp/update.tar.gz",
            observedAt: "2026-08-24T00:00:00Z"
        )
        let expected: [(
            PlatformAgentUpdateBootstrapVerificationOutcome,
            PlatformAgentUpdateBootstrapVerificationProofPolicyError
        )] = [
            (
                .spawnFailed(reason: "launcher missing"),
                .spawnFailed(reason: "launcher missing")
            ),
            (
                .commandFailed(exitCode: 2),
                .commandFailed(exitCode: 2)
            ),
            (
                .bindingMissing(path: "/tmp/binding.json"),
                .bindingMissing(path: "/tmp/binding.json")
            ),
            (
                .bindingInspectionFailed(
                    path: "/tmp/binding.json",
                    reason: "stat failed"
                ),
                .bindingInspectionFailed(
                    path: "/tmp/binding.json",
                    reason: "stat failed"
                )
            ),
            (
                .bindingPermissionDenied(
                    path: "/tmp/binding.json",
                    reason: "EACCES"
                ),
                .bindingPermissionDenied(
                    path: "/tmp/binding.json",
                    reason: "EACCES"
                )
            ),
            (
                .bindingReadFailed(path: "/tmp/binding.json", reason: "EIO"),
                .bindingReadFailed(path: "/tmp/binding.json", reason: "EIO")
            ),
            (
                .bindingDecodeFailed(
                    path: "/tmp/binding.json",
                    reason: "not json"
                ),
                .bindingDecodeFailed(
                    path: "/tmp/binding.json",
                    reason: "not json"
                )
            ),
            (
                .bindingUnexpectedPathState(
                    path: "/tmp/binding.json",
                    state: "directory"
                ),
                .bindingUnexpectedPathState(
                    path: "/tmp/binding.json",
                    state: "directory"
                )
            ),
            (
                .bindingInvalid(reason: "unsupportedSchemaVersion"),
                .bindingInvalid(reason: "unsupportedSchemaVersion")
            ),
            (
                .bindingIdentityMismatch(
                    field: "verificationInvocationId",
                    expected: "other",
                    actual: invocationId
                ),
                .bindingIdentityMismatch(
                    field: "verificationInvocationId",
                    expected: "other",
                    actual: invocationId
                )
            ),
        ]
        for (outcome, error) in expected {
            XCTAssertThrowsError(
                try PlatformAgentUpdateBootstrapVerificationProofPolicy.prove(
                    evidence: PlatformAgentUpdateBootstrapVerificationPolicy
                        .evidence(from: invoked, outcome: outcome),
                    expectedVerificationInvocationId: invocationId,
                    expectedUpdateId: "update-42",
                    expectedCanonicalPayloadSHA256: digest
                )
            ) { actual in
                XCTAssertEqual(
                    actual as?
                        PlatformAgentUpdateBootstrapVerificationProofPolicyError,
                    error
                )
            }
        }
    }

    func testValidationKeepsStatesDistinct() throws {
        try PlatformAgentUpdateBootstrapVerificationPolicy.validate(
            PlatformAgentUpdateBootstrapVerificationPolicy.invoked(
                verificationInvocationId: invocationId,
                bundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:00Z"
            )
        )
        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapVerificationPolicy.validate(
                PlatformAgentUpdateBootstrapVerificationEvidence(
                    schemaVersion:
                        PlatformAgentUpdateBootstrapVerificationContract
                        .schemaVersion,
                    producer:
                        PlatformAgentUpdateBootstrapVerificationContract
                        .producer,
                    verificationInvocationId: invocationId,
                    bundlePath: "/tmp/update.tar.gz",
                    observedAt: "2026-08-24T00:00:00Z",
                    state: PlatformAgentUpdateBootstrapVerificationContract
                        .stateSucceeded
                )
            )
        )
        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapVerificationPolicy.validate(
                PlatformAgentUpdateBootstrapVerificationEvidence(
                    schemaVersion:
                        PlatformAgentUpdateBootstrapVerificationContract
                        .schemaVersion,
                    producer: "operator-cli",
                    verificationInvocationId: invocationId,
                    bundlePath: "/tmp/update.tar.gz",
                    observedAt: "2026-08-24T00:00:00Z",
                    state: PlatformAgentUpdateBootstrapVerificationContract
                        .stateInvoked
                )
            )
        ) { error in
            XCTAssertEqual(
                error as?
                    PlatformAgentUpdateBootstrapVerificationValidationError,
                .unexpectedProducer("operator-cli")
            )
        }
    }

    func testProofRequiresSucceededStateAndMatchingIdentity() throws {
        let evidence = PlatformAgentUpdateBootstrapVerificationPolicy.evidence(
            from: PlatformAgentUpdateBootstrapVerificationPolicy.invoked(
                verificationInvocationId: invocationId,
                bundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:00Z"
            ),
            outcome: .succeeded(
                updateId: "update-42",
                canonicalPayloadSHA256: digest
            )
        )

        try PlatformAgentUpdateBootstrapVerificationProofPolicy.prove(
            evidence: evidence,
            expectedVerificationInvocationId: invocationId,
            expectedUpdateId: "update-42",
            expectedCanonicalPayloadSHA256: digest
        )
        XCTAssertThrowsError(
            try PlatformAgentUpdateBootstrapVerificationProofPolicy.prove(
                evidence: evidence,
                expectedVerificationInvocationId: invocationId,
                expectedUpdateId: "update-99",
                expectedCanonicalPayloadSHA256: digest
            )
        )
    }

    private func binding() -> UpdateBootstrapVerificationInvocationBinding {
        UpdateBootstrapVerificationInvocationBinding(
            schemaVersion:
                UpdateBootstrapVerificationInvocationBindingContract
                .schemaVersion,
            command: UpdateBootstrapVerificationInvocationBindingContract
                .command,
            verificationInvocationId: invocationId,
            updateId: "update-42",
            canonicalPayloadSHA256: digest
        )
    }

    private var invocationId: String {
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }

    private var digest: String {
        String(repeating: "ab", count: 32)
    }
}

private extension PlatformAgentUpdateBootstrapVerificationEvidence {
    func adding(
        spawnFailureReason: String
    ) -> PlatformAgentUpdateBootstrapVerificationEvidence {
        PlatformAgentUpdateBootstrapVerificationEvidence(
            schemaVersion: schemaVersion,
            producer: producer,
            verificationInvocationId: verificationInvocationId,
            bundlePath: bundlePath,
            observedAt: observedAt,
            state: state,
            updateId: updateId,
            canonicalPayloadSHA256: canonicalPayloadSHA256,
            exitCode: exitCode,
            spawnFailureReason: spawnFailureReason,
            bindingPath: bindingPath,
            bindingFailureReason: bindingFailureReason,
            bindingPathState: bindingPathState,
            identityField: identityField,
            identityExpected: identityExpected,
            identityActual: identityActual
        )
    }
}
