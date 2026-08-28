import Contracts
import Domain
import XCTest

final class UpdateBootstrapVerificationReceiptPolicyTests: XCTestCase {
    func testAcceptsInstalledHomeBoundToCurrentUpdateDigest() throws {
        XCTAssertNoThrow(
            try prove(receipt())
        )
    }

    func testRejectsInvalidBoundVerificationInvocationId() {
        XCTAssertThrowsError(
            try UpdateBootstrapVerificationReceiptPolicy.validate(
                receipt(verificationInvocationId: "")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptValidationError,
                .invalidVerificationInvocationId("")
            )
        }
    }

    func testValidationDoesNotHardcodeRootIdentity() throws {
        XCTAssertNoThrow(
            try UpdateBootstrapVerificationReceiptPolicy.validate(
                receipt(uid: 501, euid: 501)
            )
        )
    }

    func testProofRequiresExplicitUidAndEuidWithoutHardcodingRoot() throws {
        XCTAssertNoThrow(
            try prove(receipt(uid: 501, euid: 501), expectedUid: 501, expectedEuid: 501)
        )
    }

    func testRejectsUidMismatchWithoutComparingEuid() {
        XCTAssertThrowsError(
            try prove(
                receipt(uid: 501, euid: 0),
                expectedUid: 0,
                expectedEuid: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptProofPolicyError,
                .uidMismatch(expected: 0, actual: 501)
            )
        }
    }

    func testRejectsEuidMismatchWhenUidAlreadyMatches() {
        XCTAssertThrowsError(
            try prove(
                receipt(uid: 0, euid: 501),
                expectedUid: 0,
                expectedEuid: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptProofPolicyError,
                .euidMismatch(expected: 0, actual: 501)
            )
        }
    }

    func testRejectsRootDerivedRuntimeHomeWithoutUsingCurrentProcessHome() {
        XCTAssertThrowsError(
            try prove(
                receipt(resolvedRuntimeHome: "/var/root/.tirosh/vitalserver-vm")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptProofPolicyError,
                .runtimeHomeMismatch(
                    expected: installedHome,
                    actual: "/var/root/.tirosh/vitalserver-vm"
                )
            )
        }
    }

    func testRejectsDigestMismatchAsIdentityMismatchNotHomeGuess() {
        let otherDigest = String(repeating: "cd", count: 32)
        XCTAssertThrowsError(
            try prove(
                receipt(),
                expectedCanonicalPayloadSHA256: otherDigest
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptProofPolicyError,
                .identityMismatch(
                    field: "canonicalPayloadSHA256",
                    expected: otherDigest,
                    actual: digest
                )
            )
        }
    }

    func testRejectsDifferentUpdateIdWithoutReplayingPathOwner() {
        XCTAssertThrowsError(
            try prove(receipt(), expectedUpdateId: "update-99")
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptProofPolicyError,
                .identityMismatch(
                    field: "updateId",
                    expected: "update-99",
                    actual: "update-42"
                )
            )
        }
    }

    func testRejectsUnexpectedCommandAsInvalidContract() {
        XCTAssertThrowsError(
            try UpdateBootstrapVerificationReceiptPolicy.validate(
                receipt(command: "apply-update-bootstrap")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptValidationError,
                .unexpectedCommand("apply-update-bootstrap")
            )
        }
    }

    func testRejectsRelativeRuntimeHomeAsInvalidContract() {
        XCTAssertThrowsError(
            try UpdateBootstrapVerificationReceiptPolicy.validate(
                receipt(resolvedRuntimeHome: "Library/Application Support/VitalServerHelper/vm")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptValidationError,
                .invalidResolvedRuntimeHome(
                    "Library/Application Support/VitalServerHelper/vm"
                )
            )
        }
    }

    func testRejectsNonCanonicalObservedAt() {
        XCTAssertThrowsError(
            try UpdateBootstrapVerificationReceiptPolicy.validate(
                receipt(observedAt: "2026-07-27T00:00:00.000Z")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptValidationError,
                .invalidObservedAt("2026-07-27T00:00:00.000Z")
            )
        }
        XCTAssertThrowsError(
            try UpdateBootstrapVerificationReceiptPolicy.validate(
                receipt(observedAt: "2026-07-27T00:00:00+00:00")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptValidationError,
                .invalidObservedAt("2026-07-27T00:00:00+00:00")
            )
        }
        XCTAssertThrowsError(
            try UpdateBootstrapVerificationReceiptPolicy.validate(
                receipt(observedAt: "2026-02-30T00:00:00Z")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptValidationError,
                .invalidObservedAt("2026-02-30T00:00:00Z")
            )
        }
    }

    func testRejectsUnsupportedSchemaWithoutFallback() {
        XCTAssertThrowsError(
            try UpdateBootstrapVerificationReceiptPolicy.validate(
                receipt(schemaVersion: "v1")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapVerificationReceiptValidationError,
                .unsupportedSchemaVersion("v1")
            )
        }
    }

    private func prove(
        _ receipt: UpdateBootstrapVerificationReceipt,
        expectedUpdateId: String = "update-42",
        expectedCanonicalPayloadSHA256: String? = nil,
        expectedUid: UInt32 = 0,
        expectedEuid: UInt32 = 0
    ) throws {
        try UpdateBootstrapVerificationReceiptProofPolicy.prove(
            receipt: receipt,
            expectedUpdateId: expectedUpdateId,
            expectedCanonicalPayloadSHA256: expectedCanonicalPayloadSHA256
                ?? digest,
            expectedResolvedRuntimeHome: installedHome,
            expectedTrustStorePath: installedTrustStore,
            expectedUid: expectedUid,
            expectedEuid: expectedEuid
        )
    }

    private func receipt(
        schemaVersion: String = UpdateBootstrapVerificationReceiptContract
            .schemaVersion,
        command: String = UpdateBootstrapVerificationReceiptContract.command,
        resolvedRuntimeHome: String = "/Library/Application Support/VitalServerHelper/vm",
        observedAt: String = "2026-08-24T00:00:00Z",
        uid: UInt32 = 0,
        euid: UInt32 = 0,
        verificationInvocationId: String? = nil
    ) -> UpdateBootstrapVerificationReceipt {
        UpdateBootstrapVerificationReceipt(
            schemaVersion: schemaVersion,
            command: command,
            updateId: "update-42",
            canonicalPayloadSHA256: digest,
            resolvedRuntimeHome: resolvedRuntimeHome,
            trustStorePath: installedTrustStore,
            observedAt: observedAt,
            uid: uid,
            euid: euid,
            verificationInvocationId: verificationInvocationId
        )
    }

    private var digest: String {
        String(repeating: "ab", count: 32)
    }

    private var installedHome: String {
        "/Library/Application Support/VitalServerHelper/vm"
    }

    private var installedTrustStore: String {
        "/Library/Application Support/VitalServerHelper/config/update-bootstrap-trust-store.json"
    }
}
