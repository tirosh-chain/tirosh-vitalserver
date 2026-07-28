import Contracts
import Foundation
import XCTest

final class RuntimeContainerImageSetContractsTests: XCTestCase {
    func testUnavailableReadRequiresFailureInsteadOfEmptySuccess() {
        let data = Data(
            """
            {
              "state": "unavailable",
              "imageSet": null,
              "observedAt": "2026-07-29T00:00:00Z",
              "failure": null
            }
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(
            RuntimeContainerImageSetRead.self,
            from: data
        ))
    }

    func testImageSetRejectsNonCanonicalDigest() {
        let data = Data(
            #"{"identity":"images-0.2.2","digest":"latest"}"#.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(
            RuntimeContainerImageSet.self,
            from: data
        ))
    }

    func testUnavailableOperationRetainsTypedFailure() throws {
        let data = Data(
            """
            {
              "operationId": "container-op-1",
              "command": "apply",
              "expectedCurrentIdentity": "images-0.2.1",
              "target": {
                "identity": "images-0.2.2",
                "digest": "sha256:\(String(repeating: "b", count: 64))"
              },
              "state": "unavailable",
              "createdAt": "2026-07-29T00:00:00Z",
              "updatedAt": "2026-07-29T00:00:01Z",
              "failure": {
                "kind": "containerExecutorUnavailable",
                "message": "No executor is configured."
              }
            }
            """.utf8
        )

        let operation = try JSONDecoder().decode(
            RuntimeContainerImageSetOperation.self,
            from: data
        )

        XCTAssertEqual(operation.state, .unavailable)
        XCTAssertEqual(operation.failure?.kind, "containerExecutorUnavailable")
    }
}
