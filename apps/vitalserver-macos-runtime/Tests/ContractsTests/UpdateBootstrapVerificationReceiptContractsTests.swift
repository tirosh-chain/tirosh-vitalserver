import Contracts
import XCTest

final class UpdateBootstrapVerificationReceiptContractsTests: XCTestCase {
    func testDecodesStrictReceipt() throws {
        let receipt = try JSONDecoder().decode(
            UpdateBootstrapVerificationReceipt.self,
            from: Data(document.utf8)
        )

        XCTAssertEqual(
            receipt.schemaVersion,
            UpdateBootstrapVerificationReceiptContract.schemaVersion
        )
        XCTAssertEqual(
            receipt.command,
            UpdateBootstrapVerificationReceiptContract.command
        )
        XCTAssertEqual(receipt.updateId, "update-42")
        XCTAssertEqual(receipt.canonicalPayloadSHA256, digest)
        XCTAssertEqual(
            receipt.resolvedRuntimeHome,
            "/Library/Application Support/VitalServerHelper/vm"
        )
        XCTAssertEqual(receipt.uid, 0)
        XCTAssertEqual(receipt.euid, 0)
        XCTAssertNil(receipt.verificationInvocationId)
    }

    func testRoundTripsExplicitFields() throws {
        let original = receipt()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            UpdateBootstrapVerificationReceipt.self,
            from: encoded
        )

        XCTAssertEqual(decoded, original)
    }

    func testRejectsUnknownField() {
        let invalid = document.dropLast() + #","legacyHome":"/var/root/.tirosh"}"#

        XCTAssertThrowsError(try JSONDecoder().decode(
            UpdateBootstrapVerificationReceipt.self,
            from: Data(invalid.utf8)
        ))
    }

    func testRejectsMissingUidWithoutDefaulting() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            UpdateBootstrapVerificationReceipt.self,
            from: Data(
                """
                {"schemaVersion":"\(UpdateBootstrapVerificationReceiptContract.schemaVersion)","command":"verify-update-bootstrap","updateId":"update-42","canonicalPayloadSHA256":"\(digest)","resolvedRuntimeHome":"/Library/Application Support/VitalServerHelper/vm","trustStorePath":"/Library/Application Support/VitalServerHelper/config/update-bootstrap-trust-store.json","observedAt":"2026-08-24T00:00:00Z","euid":0}
                """.utf8
            )
        ))
    }

    func testFileNameBindsUpdateId() {
        XCTAssertEqual(
            UpdateBootstrapVerificationReceiptContract.fileName(
                updateId: "update-42"
            ),
            "update-42.json"
        )
        XCTAssertEqual(
            UpdateBootstrapVerificationReceiptContract.directoryName,
            "update-bootstrap-verification"
        )
    }

    private func receipt() -> UpdateBootstrapVerificationReceipt {
        UpdateBootstrapVerificationReceipt(
            schemaVersion: UpdateBootstrapVerificationReceiptContract
                .schemaVersion,
            command: UpdateBootstrapVerificationReceiptContract.command,
            updateId: "update-42",
            canonicalPayloadSHA256: digest,
            resolvedRuntimeHome:
                "/Library/Application Support/VitalServerHelper/vm",
            trustStorePath:
                "/Library/Application Support/VitalServerHelper/config/update-bootstrap-trust-store.json",
            observedAt: "2026-08-24T00:00:00Z",
            uid: 0,
            euid: 0
        )
    }

    private var digest: String {
        String(repeating: "ab", count: 32)
    }

    private var document: String {
        """
        {"schemaVersion":"\(UpdateBootstrapVerificationReceiptContract.schemaVersion)","command":"verify-update-bootstrap","updateId":"update-42","canonicalPayloadSHA256":"\(digest)","resolvedRuntimeHome":"/Library/Application Support/VitalServerHelper/vm","trustStorePath":"/Library/Application Support/VitalServerHelper/config/update-bootstrap-trust-store.json","observedAt":"2026-08-24T00:00:00Z","uid":0,"euid":0}
        """
    }
}
