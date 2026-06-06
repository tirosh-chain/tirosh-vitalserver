import Contracts
import XCTest
import Errors

final class RedisBackupDocumentsTests: XCTestCase {
    func testRequestDocumentEncodesRedisBackupOperation() throws {
        let document = RedisBackupRequestDocument(
            requestId: "request-1",
            requestedAt: "2026-06-05T00:00:00Z"
        )

        let decoded = try JSONDecoder().decode(
            RedisBackupRequestDocument.self,
            from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.requestId, "request-1")
        XCTAssertEqual(decoded.requestedAt, "2026-06-05T00:00:00Z")
        XCTAssertEqual(decoded.operation, .redisBackup)
    }

    func testResultDocumentDecodesCompletedArchive() throws {
        let json = """
        {
          "requestId": "request-1",
          "status": "completed",
          "message": "done",
          "archive": "/tmp/redis.tar"
        }
        """

        let document = try JSONDecoder().decode(RedisBackupResultDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.requestId, "request-1")
        XCTAssertEqual(document.status, .completed)
        XCTAssertEqual(document.message, "done")
        XCTAssertEqual(document.archive, "/tmp/redis.tar")
    }
}
