import Contracts
import XCTest

final class PlatformAgentUpdateBootstrapVerificationContractsTests: XCTestCase {
    func testDecodesSucceededEvidenceAndOmitsNullOptionalFields() throws {
        let evidence = try JSONDecoder().decode(
            PlatformAgentUpdateBootstrapVerificationEvidence.self,
            from: Data(succeededDocument.utf8)
        )

        XCTAssertEqual(
            evidence.producer,
            PlatformAgentUpdateBootstrapVerificationContract.producer
        )
        XCTAssertEqual(evidence.state, "succeeded")
        XCTAssertEqual(evidence.updateId, "update-42")
        XCTAssertNil(evidence.exitCode)
        XCTAssertNil(evidence.spawnFailureReason)
        XCTAssertNil(evidence.bindingPath)
        XCTAssertNil(evidence.bindingFailureReason)
    }

    func testDecodesTypedBindingMissingWithoutAReceiptMismatchReason() throws {
        let evidence = try JSONDecoder().decode(
            PlatformAgentUpdateBootstrapVerificationEvidence.self,
            from: Data(
                """
                {"schemaVersion":"\(PlatformAgentUpdateBootstrapVerificationContract.schemaVersion)","producer":"MacPlatformAgent","verificationInvocationId":"\(invocationId)","bundlePath":"/tmp/update.tar.gz","observedAt":"2026-08-24T00:00:00Z","state":"bindingMissing","bindingPath":"/tmp/binding.json"}
                """.utf8
            )
        )

        XCTAssertEqual(
            evidence.state,
            PlatformAgentUpdateBootstrapVerificationContract.stateBindingMissing
        )
        XCTAssertEqual(evidence.bindingPath, "/tmp/binding.json")
        XCTAssertNil(evidence.bindingFailureReason)
    }

    func testRejectsNullOptionalField() {
        let invalid = succeededDocument.dropLast()
            + #","spawnFailureReason":null}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PlatformAgentUpdateBootstrapVerificationEvidence.self,
                from: Data(invalid.utf8)
            )
        )
    }

    func testRoundTripOmitsNilFields() throws {
        let original = PlatformAgentUpdateBootstrapVerificationEvidence(
            schemaVersion:
                PlatformAgentUpdateBootstrapVerificationContract.schemaVersion,
            producer: PlatformAgentUpdateBootstrapVerificationContract.producer,
            verificationInvocationId: invocationId,
            bundlePath: "/tmp/update.tar.gz",
            observedAt: "2026-08-24T00:00:00Z",
            state: PlatformAgentUpdateBootstrapVerificationContract.stateInvoked
        )
        let encoded = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let keys = (object as? [String: Any]).map { Set($0.keys) }

        XCTAssertEqual(
            keys,
            [
                "schemaVersion",
                "producer",
                "verificationInvocationId",
                "bundlePath",
                "observedAt",
                "state",
            ]
        )
        let decoded = try JSONDecoder().decode(
            PlatformAgentUpdateBootstrapVerificationEvidence.self,
            from: encoded
        )
        XCTAssertEqual(decoded, original)
    }

    private var invocationId: String {
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }

    private var succeededDocument: String {
        """
        {"schemaVersion":"\(PlatformAgentUpdateBootstrapVerificationContract.schemaVersion)","producer":"MacPlatformAgent","verificationInvocationId":"\(invocationId)","bundlePath":"/tmp/update.tar.gz","observedAt":"2026-08-24T00:00:00Z","state":"succeeded","updateId":"update-42","canonicalPayloadSHA256":"\(String(repeating: "ab", count: 32))"}
        """
    }
}
