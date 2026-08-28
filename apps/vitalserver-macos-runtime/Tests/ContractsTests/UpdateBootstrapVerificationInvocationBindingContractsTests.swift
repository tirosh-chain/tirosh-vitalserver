import Contracts
import XCTest

final class UpdateBootstrapVerificationInvocationBindingContractsTests:
    XCTestCase
{
    func testDecodesStrictBinding() throws {
        let binding = try JSONDecoder().decode(
            UpdateBootstrapVerificationInvocationBinding.self,
            from: Data(document.utf8)
        )

        XCTAssertEqual(
            binding.schemaVersion,
            UpdateBootstrapVerificationInvocationBindingContract.schemaVersion
        )
        XCTAssertEqual(binding.verificationInvocationId, invocationId)
        XCTAssertEqual(binding.updateId, "update-42")
        XCTAssertEqual(binding.canonicalPayloadSHA256, digest)
    }

    func testRejectsUnknownField() {
        let invalid = document.dropLast() + #","caller":"cli"}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UpdateBootstrapVerificationInvocationBinding.self,
                from: Data(invalid.utf8)
            )
        )
    }

    func testFileNameBindsInvocationId() {
        XCTAssertEqual(
            UpdateBootstrapVerificationInvocationBindingContract.fileName(
                verificationInvocationId: invocationId
            ),
            "\(invocationId).json"
        )
    }

    private var invocationId: String {
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }

    private var digest: String {
        String(repeating: "ab", count: 32)
    }

    private var document: String {
        """
        {"schemaVersion":"\(UpdateBootstrapVerificationInvocationBindingContract.schemaVersion)","command":"verify-update-bootstrap","verificationInvocationId":"\(invocationId)","updateId":"update-42","canonicalPayloadSHA256":"\(digest)"}
        """
    }
}
