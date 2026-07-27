import Foundation
import OutboundAdapters
import XCTest

final class UpdateBootstrapTrustStoreReaderTests: XCTestCase {
    func testLoadsDecodedPublicKeyByOwnerId() throws {
        let file = try write(
            """
            {"schemaVersion":"v1","keys":[{"id":"release-key","algorithm":"ed25519","publicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}]}
            """
        )
        defer {
            try? FileManager.default.removeItem(at: file)
        }

        let keys = try UpdateBootstrapTrustStoreReader().loadPublicKeys(from: file)

        XCTAssertEqual(keys["release-key"], Data(repeating: 0, count: 32))
    }

    func testReportsMissingTrustStoreAsUnavailable() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        XCTAssertThrowsError(
            try UpdateBootstrapTrustStoreReader().loadPublicKeys(from: file)
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapTrustStoreLoadError,
                .unavailable(path: file.path)
            )
        }
    }

    func testReportsMalformedDocumentAsDecodeFailure() throws {
        let file = try write("{")
        defer {
            try? FileManager.default.removeItem(at: file)
        }

        XCTAssertThrowsError(
            try UpdateBootstrapTrustStoreReader().loadPublicKeys(from: file)
        ) { error in
            guard case .decodeFailed(let path, _) =
                    error as? UpdateBootstrapTrustStoreLoadError else {
                return XCTFail("expected decode failure, got \(error)")
            }
            XCTAssertEqual(path, file.path)
        }
    }

    private func write(_ text: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: file)
        return file
    }
}
