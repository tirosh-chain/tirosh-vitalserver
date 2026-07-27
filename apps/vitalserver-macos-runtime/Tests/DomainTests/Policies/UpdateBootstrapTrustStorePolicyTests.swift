import Contracts
import Domain
import XCTest

final class UpdateBootstrapTrustStorePolicyTests: XCTestCase {
    func testAcceptsUniqueEd25519PublisherKeys() throws {
        try UpdateBootstrapTrustStorePolicy.validate(store())
    }

    func testRejectsDuplicateKeyOwner() {
        let key = publisherKey()
        XCTAssertThrowsError(try UpdateBootstrapTrustStorePolicy.validate(
            UpdateBootstrapTrustStore(schemaVersion: "v1", keys: [key, key])
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapTrustStoreValidationError,
                .duplicateKeyId("release-key")
            )
        }
    }

    func testRejectsEmptyTrustStore() {
        XCTAssertThrowsError(try UpdateBootstrapTrustStorePolicy.validate(
            UpdateBootstrapTrustStore(schemaVersion: "v1", keys: [])
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapTrustStoreValidationError,
                .emptyKeys
            )
        }
    }

    private func store() -> UpdateBootstrapTrustStore {
        UpdateBootstrapTrustStore(
            schemaVersion: "v1",
            keys: [publisherKey()]
        )
    }

    private func publisherKey() -> TrustedUpdatePublisherKey {
        TrustedUpdatePublisherKey(
            id: "release-key",
            algorithm: .ed25519,
            publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )
    }
}
