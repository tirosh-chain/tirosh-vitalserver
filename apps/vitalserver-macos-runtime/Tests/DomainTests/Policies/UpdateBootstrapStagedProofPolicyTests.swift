import Contracts
import Domain
import XCTest

final class UpdateBootstrapStagedProofPolicyTests: XCTestCase {
    func testAcceptsMatchingSourceAndStagedProof() throws {
        let proof = closure()
        try UpdateBootstrapStagedProofPolicy.requireMatch(
            source: proof,
            staged: proof
        )
    }

    func testRejectsPayloadArtifactSetMismatch() {
        XCTAssertThrowsError(
            try UpdateBootstrapStagedProofPolicy.requireMatch(
                source: closure(),
                staged: closure(payloadIds: ["tampered-artifact"])
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapStagedProofError,
                .payloadArtifactSetMismatch(
                    expected: ["host-artifact"],
                    actual: ["tampered-artifact"]
                )
            )
        }
    }

    private func closure(
        payloadIds: [String] = ["host-artifact"]
    ) -> VerifiedUpdateBootstrapClosure {
        VerifiedUpdateBootstrapClosure(
            updateId: "update-42",
            canonicalPayloadSHA256: String(repeating: "a", count: 64),
            verifiedBootstrapArtifactIds: [
                "next-updater",
                "update-specification",
            ],
            verifiedPayloadArtifactIds: payloadIds
        )
    }
}
