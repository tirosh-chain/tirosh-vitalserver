import Contracts
import Foundation
import XCTest

final class UpdateInstallationFenceContractTests: XCTestCase {
    func testOperationLeaseVersionTwoRequiresExplicitInstallationTargetKeys() {
        let data = Data(
            """
            {
              "schemaVersion": 2,
              "operationId": "operation-1",
              "operation": "apply-update-bootstrap",
              "ownerPID": 123,
              "startedAt": "2026-07-29T00:00:00Z",
              "heartbeatAt": "2026-07-29T00:00:00Z",
              "expiresAt": null,
              "message": null
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RuntimeOperationLeaseDocument.self,
                from: data
            )
        )
    }

    func testOperationLeaseVersionOneIsAnExplicitUnboundLegacyContract() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "operationId": "operation-legacy",
              "operation": "apply-bundle",
              "ownerPID": 123,
              "startedAt": "2026-07-28T00:00:00Z",
              "heartbeatAt": "2026-07-28T00:00:00Z",
              "expiresAt": null,
              "message": null
            }
            """.utf8
        )

        let document = try JSONDecoder().decode(
            RuntimeOperationLeaseDocument.self,
            from: data
        )

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertNil(document.targetInstallationId)
        XCTAssertNil(document.expectedInstallationRevision)
    }

    func testUpdateJournalRejectsMissingInstallationFence() {
        let encoded = """
            {
              "schemaVersion": "v2",
              "id": "update-1",
              "journalRevision": 1,
              "operationId": "operation-1",
              "requestId": "request-1"
            }
            """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                UpdateBootstrapJournal.self,
                from: Data(encoded.utf8)
            )
        )
    }
}
