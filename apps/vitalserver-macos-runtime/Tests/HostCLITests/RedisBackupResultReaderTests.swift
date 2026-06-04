import Foundation
import RuntimeWorkflow
@testable import HostCLI
import XCTest

final class RedisBackupResultReaderTests: XCTestCase {
    func testDistinguishesMissingLoadedAndInvalidResultDocuments() {
        let fileStore = RuntimeFileStoreSpy()
        let resultURL = URL(fileURLWithPath: "/tmp/redis-backup-result.json")

        guard case .missing = RedisBackupResultReader.load(from: resultURL, fileStore: fileStore) else {
            return XCTFail("Expected missing result when the result document is absent")
        }

        fileStore.files[resultURL] = Data("""
        {
          "requestId": "request-1",
          "status": "completed",
          "message": "done",
          "archive": "/tmp/redis.tar"
        }
        """.utf8)

        guard case .loaded(let document) = RedisBackupResultReader.load(from: resultURL, fileStore: fileStore) else {
            return XCTFail("Expected loaded result when the result document is valid")
        }
        XCTAssertEqual(document.requestId, "request-1")
        XCTAssertEqual(document.status, .completed)
        XCTAssertEqual(document.message, "done")
        XCTAssertEqual(document.archive, "/tmp/redis.tar")

        fileStore.files[resultURL] = Data("{".utf8)
        guard case .failed(let message) = RedisBackupResultReader.load(from: resultURL, fileStore: fileStore) else {
            return XCTFail("Expected failed result when the result document cannot be decoded")
        }
        XCTAssertFalse(message.isEmpty)
    }
}
