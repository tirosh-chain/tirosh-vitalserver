import Contracts
import XCTest

final class UpdateBootstrapTrustStoreContractsTests: XCTestCase {
    func testDecodesStrictTrustStore() throws {
        let store = try JSONDecoder().decode(
            UpdateBootstrapTrustStore.self,
            from: Data(
                """
                {"schemaVersion":"v1","keys":[{"id":"release-key","algorithm":"ed25519","publicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}]}
                """.utf8
            )
        )

        XCTAssertEqual(store.schemaVersion, "v1")
        XCTAssertEqual(store.keys.map(\.id), ["release-key"])
    }

    func testRejectsUnknownKeyPurposeField() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            UpdateBootstrapTrustStore.self,
            from: Data(
                """
                {"schemaVersion":"v1","keys":[{"id":"release-key","algorithm":"ed25519","publicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","purpose":"update"}]}
                """.utf8
            )
        ))
    }
}
