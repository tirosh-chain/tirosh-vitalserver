import Contracts
import XCTest

final class GuestRuntimeStateDocumentTests: XCTestCase {
    func testDecodesRuntimeStateWithoutVitalDBObservationContractField() throws {
        let json = """
        {
          "vmIP": "192.168.64.2",
          "updatedAt": "2026-05-24T00:00:00Z",
          "bootID": "boot-current",
          "guestHTTP": "200",
          "redisUIHTTP": "200",
          "swaggerUIHTTP": "200",
          "vitalDBObservation": {
            "source": "legacy-runtime-state",
            "observedAt": "2026-05-24T00:00:00Z",
            "ready": false,
            "recorderOnlineThresholdSeconds": 60
          }
        }
        """

        let document = try JSONDecoder().decode(
            GuestRuntimeStateDocument.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(document.vmIP, "192.168.64.2")
        XCTAssertEqual(document.guestHTTP, "200")
    }
}
