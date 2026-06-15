import Foundation
import Contracts
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

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

    func testPreservesResultPathInspectionFailures() {
        let fileStore = RuntimeFileStoreSpy()
        let resultURL = URL(fileURLWithPath: "/tmp/redis-backup-result.json")

        fileStore.pathStates[resultURL.path] = .inspectFailed("permission denied")
        guard case .failed(let inspectionMessage) = RedisBackupResultReader.load(from: resultURL, fileStore: fileStore) else {
            return XCTFail("Expected failed result when path inspection fails")
        }
        XCTAssertEqual(
            inspectionMessage,
            "redis backup result path inspection failed path=/tmp/redis-backup-result.json reason=permission denied"
        )

        fileStore.pathStates[resultURL.path] = .directory
        guard case .failed(let unexpectedStateMessage) = RedisBackupResultReader.load(from: resultURL, fileStore: fileStore) else {
            return XCTFail("Expected failed result when path state is unexpected")
        }
        XCTAssertEqual(
            unexpectedStateMessage,
            "redis backup result path state is unexpected path=/tmp/redis-backup-result.json state=directory"
        )
    }
}
