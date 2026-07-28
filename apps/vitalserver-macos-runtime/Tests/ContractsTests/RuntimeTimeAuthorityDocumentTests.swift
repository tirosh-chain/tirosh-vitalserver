import XCTest
@testable import Contracts

final class RuntimeTimeAuthorityDocumentTests: XCTestCase {
    func testDecodesGuestClockQualityEvidence() throws {
        let data = Data(
            """
            {
              "state": "synchronized",
              "observedAt": "2026-07-28T07:25:32+00:00",
              "source": "192.168.64.1",
              "stratum": 11,
              "offsetMs": -0.25,
              "uncertaintyMs": 0.8,
              "rootDelayMs": 0.1,
              "rootDispersionMs": 0.8,
              "lastSyncAt": "2026-07-28T07:25:31+00:00"
            }
            """.utf8
        )

        let quality = try JSONDecoder().decode(
            RuntimeClockQualityDocument.self,
            from: data
        )

        XCTAssertEqual(quality.state, .synchronized)
        XCTAssertEqual(quality.source, "192.168.64.1")
        XCTAssertEqual(quality.offsetMs, -0.25)
        XCTAssertEqual(quality.uncertaintyMs, 0.8)
        XCTAssertEqual(quality.lastSyncAt, "2026-07-28T07:25:31+00:00")
    }

    func testRoundTripsExplicitHelperClockContract() throws {
        let document = RuntimeTimeAuthorityDocument(
            profile: .helperNTP,
            sourceId: "helper-host-clock",
            serverAddress: "192.168.64.1",
            serverPort: 123,
            state: .hostClockOnly,
            stratum: 10,
            allowedClientAddress: "192.168.64.3",
            updatedAt: "2026-07-28T07:25:32Z"
        )

        let decoded = try JSONDecoder().decode(
            RuntimeTimeAuthorityDocument.self,
            from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(RuntimeHostContractFileNames.timeAuthority, "time-authority.json")
    }

    func testPreservesUnavailableWithoutInventingServerState() throws {
        let document = RuntimeTimeAuthorityDocument(
            profile: .helperNTP,
            sourceId: "helper-host-clock",
            serverAddress: nil,
            serverPort: nil,
            state: .unavailable,
            stratum: nil,
            allowedClientAddress: nil,
            updatedAt: "2026-07-28T07:25:32Z",
            issue: "Guest address is missing"
        )

        let decoded = try JSONDecoder().decode(
            RuntimeTimeAuthorityDocument.self,
            from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded, document)
    }
}
