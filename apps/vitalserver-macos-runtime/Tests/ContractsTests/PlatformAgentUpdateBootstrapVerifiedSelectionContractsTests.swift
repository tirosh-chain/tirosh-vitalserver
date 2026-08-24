import Contracts
import XCTest

final class PlatformAgentUpdateBootstrapVerifiedSelectionContractsTests:
    XCTestCase
{
    func testDecodesVerifiedSelectionAndOmitsBoundRequestId() throws {
        let selection = try JSONDecoder().decode(
            PlatformAgentUpdateBootstrapVerifiedSelection.self,
            from: Data(verifiedDocument.utf8)
        )

        XCTAssertEqual(
            selection.producer,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.producer
        )
        XCTAssertEqual(
            selection.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateVerified
        )
        XCTAssertNil(selection.journalCorrelation)
        XCTAssertEqual(selection.selectionId, selectionId)
        XCTAssertEqual(selection.verificationInvocationId, invocationId)
        XCTAssertEqual(selection.updateId, "update-42")
        XCTAssertEqual(selection.canonicalPayloadSHA256, digest)
        XCTAssertEqual(selection.observedBundlePath, "/tmp/update.tar.gz")
        XCTAssertNil(selection.boundRequestId)
    }

    func testRoundTripOmitsNilBoundRequestId() throws {
        let original = verifiedSelection()
        let encoded = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let keys = (object as? [String: Any]).map { Set($0.keys) }

        XCTAssertEqual(
            keys,
            [
                "schemaVersion",
                "producer",
                "selectionId",
                "verificationInvocationId",
                "updateId",
                "canonicalPayloadSHA256",
                "observedBundlePath",
                "state",
                "observedAt",
            ]
        )
        let decoded = try JSONDecoder().decode(
            PlatformAgentUpdateBootstrapVerifiedSelection.self,
            from: encoded
        )
        XCTAssertEqual(decoded, original)
    }

    func testRejectsNullBoundRequestId() {
        let invalid = verifiedDocument.dropLast() + #","boundRequestId":null}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PlatformAgentUpdateBootstrapVerifiedSelection.self,
                from: Data(invalid.utf8)
            )
        )
    }

    func testRejectsUnknownField() {
        let invalid = verifiedDocument.dropLast() + #","latest":true}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PlatformAgentUpdateBootstrapVerifiedSelection.self,
                from: Data(invalid.utf8)
            )
        )
    }

    func testCurrentFileNameIsStable() {
        XCTAssertEqual(
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.fileName,
            "current.json"
        )
        XCTAssertEqual(
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.directoryName,
            "platform-agent-update-bootstrap-selection"
        )
    }

    private func verifiedSelection() -> PlatformAgentUpdateBootstrapVerifiedSelection {
        PlatformAgentUpdateBootstrapVerifiedSelection(
            schemaVersion:
                PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .schemaVersion,
            producer: PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .producer,
            selectionId: selectionId,
            verificationInvocationId: invocationId,
            updateId: "update-42",
            canonicalPayloadSHA256: digest,
            observedBundlePath: "/tmp/update.tar.gz",
            state: PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .stateVerified,
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

    private var verifiedDocument: String {
        """
        {"schemaVersion":"\(PlatformAgentUpdateBootstrapVerifiedSelectionContract.schemaVersion)","producer":"MacPlatformAgent","selectionId":"\(selectionId)","verificationInvocationId":"\(invocationId)","updateId":"update-42","canonicalPayloadSHA256":"\(digest)","observedBundlePath":"/tmp/update.tar.gz","state":"verified","observedAt":"2026-08-24T00:00:00Z"}
        """
    }
}
