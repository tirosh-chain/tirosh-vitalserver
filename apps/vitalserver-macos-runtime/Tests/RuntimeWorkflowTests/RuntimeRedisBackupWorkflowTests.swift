import Contracts
import Foundation
import Workflow
import XCTest

final class RuntimeRedisBackupWorkflowTests: XCTestCase {
    func testCreateBackupWritesRequestStartsVMWaitsForCompletedResultAndReturnsArchive() throws {
        let harness = Harness(results: [
            .missing,
            .loaded(RedisBackupResultDocument(
                requestId: "request-1",
                status: .completed,
                message: "done",
                archive: "/backups/redis.tar"
            )),
        ])

        let result = try harness.workflow.createBackup()

        XCTAssertEqual(result, RuntimeRedisBackupResult(message: "done", archive: "/backups/redis.tar"))
        XCTAssertEqual(harness.events, [
            "log:redis backup requested",
            "capability",
            "create:/guest/run:true",
            "create:/redis/backups:true",
            "remove-previous:/guest/run/redis-backup-result.json",
            "status:recovering:redis-backup:redis backup requested",
            "request:/guest/run/redis-backup-request.json:request-1:2026-06-05T00:00:00Z",
            "vm-loaded",
            "start-vm",
            "load:/guest/run/redis-backup-result.json",
            "log:waiting for redis backup guest worker",
            "sleep:3.0",
            "load:/guest/run/redis-backup-result.json",
            "status:healthy:redis-backup:done",
            "log:redis backup completed",
        ])
    }

    func testCreateBackupIgnoresStaleResultUntilMatchingResultCompletes() throws {
        let harness = Harness(results: [
            .loaded(RedisBackupResultDocument(
                requestId: "stale-request",
                status: .completed,
                message: "stale",
                archive: nil
            )),
            .loaded(RedisBackupResultDocument(
                requestId: "request-1",
                status: .completed,
                message: nil,
                archive: nil
            )),
        ])
        harness.vmLoaded = true

        let result = try harness.workflow.createBackup()

        XCTAssertEqual(result, RuntimeRedisBackupResult(message: "Redis backup completed.", archive: nil))
        XCTAssertTrue(harness.events.contains("log:stale redis backup result ignored"))
        XCTAssertFalse(harness.events.contains("start-vm"))
    }

    func testCreateBackupWritesDegradedStatusAndFailsWhenGuestReportsFailure() {
        let harness = Harness(results: [
            .loaded(RedisBackupResultDocument(
                requestId: "request-1",
                status: .failed,
                message: "backup failed",
                archive: nil
            )),
        ])

        XCTAssertThrowsError(try harness.workflow.createBackup()) { error in
            XCTAssertEqual(errorDescription(error), "backup failed")
        }
        XCTAssertTrue(harness.events.contains("status:degraded:redis-backup:backup failed"))
    }

    func testCreateBackupFailsOnUnreadableResultAndOnTimeout() {
        let unreadable = Harness(results: [.failed("permission denied")])

        XCTAssertThrowsError(try unreadable.workflow.createBackup()) { error in
            XCTAssertEqual(errorDescription(error), "failed to read redis backup result: permission denied")
        }
        XCTAssertTrue(unreadable.events.contains(
            "status:degraded:redis-backup:failed to read redis backup result: permission denied"
        ))

        let timeout = Harness(results: [.missing, .missing])
        XCTAssertThrowsError(try timeout.workflow.createBackup()) { error in
            XCTAssertEqual(errorDescription(error), "redis backup timed out")
        }
        XCTAssertTrue(timeout.events.contains("status:degraded:redis-backup:redis backup timed out"))
    }

    private func errorDescription(_ error: Error) -> String {
        if case RuntimeRedisBackupWorkflowError.operationFailed(let message) = error {
            return message
        }
        return String(describing: error)
    }

    final class Harness {
        var events: [String] = []
        var results: [RuntimeRedisBackupResultLoadResult]
        var vmLoaded = false

        lazy var workflow = RuntimeRedisBackupWorkflow(
            context: RuntimeRedisBackupWorkflowContext(
                guestRunDirectory: URL(fileURLWithPath: "/guest/run"),
                redisBackupsDirectory: URL(fileURLWithPath: "/redis/backups"),
                requestFileName: "redis-backup-request.json",
                resultFileName: "redis-backup-result.json",
                waitTimeoutSeconds: 6,
                pollIntervalSeconds: 3
            ),
            operations: RuntimeRedisBackupWorkflowOperations(
                requireCapability: { [self] in events.append("capability") },
                createDirectory: { [self] url, withIntermediateDirectories in
                    events.append("create:\(url.path):\(withIntermediateDirectories)")
                },
                removePreviousResult: { [self] url in
                    events.append("remove-previous:\(url.path)")
                },
                writeStatus: { [self] status, operation, message in
                    events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
                },
                requestID: { "request-1" },
                timestamp: { "2026-06-05T00:00:00Z" },
                writeRequest: { [self] request, url in
                    events.append("request:\(url.path):\(request.requestId):\(request.requestedAt)")
                },
                isVMServiceLoaded: { [self] in
                    events.append("vm-loaded")
                    return vmLoaded
                },
                startVMService: { [self] in events.append("start-vm") },
                loadResult: { [self] url in
                    events.append("load:\(url.path)")
                    guard !results.isEmpty else {
                        return .missing
                    }
                    return results.removeFirst()
                },
                sleep: { [self] seconds in events.append("sleep:\(seconds)") },
                log: { [self] message in events.append("log:\(message)") }
            )
        )

        init(results: [RuntimeRedisBackupResultLoadResult]) {
            self.results = results
        }
    }
}
