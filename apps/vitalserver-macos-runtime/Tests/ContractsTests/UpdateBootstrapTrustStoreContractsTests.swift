import Contracts
import XCTest

final class UpdateBootstrapTrustStoreContractsTests: XCTestCase {
    func testDecodesStrictTrustStore() throws {
        let store = try JSONDecoder().decode(
            UpdateBootstrapTrustStore.self,
            from: Data(
                """
                {"schemaVersion":"v2","keys":[{"id":"release-key","algorithm":"ed25519","publicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","state":"active"}]}
                """.utf8
            )
        )

        XCTAssertEqual(store.schemaVersion, "v2")
        XCTAssertEqual(store.keys.map(\.id), ["release-key"])
    }

    func testRejectsUnknownKeyPurposeField() {
        XCTAssertThrowsError(try JSONDecoder().decode(
            UpdateBootstrapTrustStore.self,
            from: Data(
                """
                {"schemaVersion":"v2","keys":[{"id":"release-key","algorithm":"ed25519","publicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","state":"active","purpose":"update"}]}
                """.utf8
            )
        ))
    }
}
