import Contracts
import Foundation
import XCTest

final class RuntimeGuestReleaseContractsTests: XCTestCase {
    func testUnavailableReadRequiresTypedFailure() {
        let data = Data(
            """
            {
              "state": "unavailable",
              "release": null,
              "observedAt": "2026-07-29T00:00:00Z",
              "failure": null
            }
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(
            RuntimeGuestReleaseRead.self,
            from: data
        ))
    }

    func testReleaseRejectsNonCanonicalArchiveDigest() {
        let data = Data(
            #"{"identity":"guest-0.2.2","archive":"releases/guest.tar","digest":"latest"}"#.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(
            RuntimeGuestRelease.self,
            from: data
        ))
    }

    func testUnavailableOperationPreservesFailure() throws {
        let operation = try JSONDecoder().decode(
            RuntimeGuestReleaseOperation.self,
            from: Data(guestReleaseOperationJSON(
                command: "apply",
                state: "unavailable",
                failure: """
                {
                  "kind": "guestRuntimeExecutorUnavailable",
                  "message": "No executor is configured."
                }
                """
            ).utf8)
        )

        XCTAssertEqual(operation.state, .unavailable)
        XCTAssertEqual(operation.failure?.kind, "guestRuntimeExecutorUnavailable")
    }
}

private func guestReleaseOperationJSON(
    command: String,
    state: String,
    failure: String
) -> String {
    """
    {
      "operationId": "guest-release-\(command)-1",
      "command": "\(command)",
      "expectedActiveIdentity": "guest-0.2.1",
      "target": {
        "identity": "guest-0.2.2",
        "archive": "releases/guest-0.2.2.tar",
        "digest": "sha256:\(String(repeating: "b", count: 64))"
      },
      "state": "\(state)",
      "createdAt": "2026-07-29T00:00:00Z",
      "updatedAt": "2026-07-29T00:00:01Z",
      "failure": \(failure)
    }
    """
}
