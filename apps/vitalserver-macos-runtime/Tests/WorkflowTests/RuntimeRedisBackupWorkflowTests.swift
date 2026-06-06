import Application
import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeRedisBackupWorkflowTests: XCTestCase {
    func testCreateRedisBackupExecutesPortsAndReturnsCompletedResult() throws {
        let harness = RedisBackupHarness(results: [
            .missing,
            .loaded(redisResult(status: .completed, requestId: "request-1", message: "done", archive: "/backups/redis.tar")),
        ])

        let result = try harness.workflow.createBackup(context: harness.context, actions: harness.actions)

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

    func testCreateRedisBackupPreservesStaleFailureUnreadableAndTimeoutMeanings() throws {
        let stale = RedisBackupHarness(results: [
            .loaded(redisResult(status: .completed, requestId: "stale-request", message: "stale")),
            .loaded(redisResult(status: .completed, requestId: "request-1", message: nil)),
        ])
        stale.vmLoaded = true

        let staleResult = try stale.workflow.createBackup(context: stale.context, actions: stale.actions)

        XCTAssertEqual(staleResult, RuntimeRedisBackupResult(message: "Redis backup completed.", archive: nil))
        XCTAssertTrue(stale.events.contains("log:stale redis backup result ignored"))
        XCTAssertFalse(stale.events.contains("start-vm"))

        let failed = RedisBackupHarness(results: [
            .loaded(redisResult(status: .failed, requestId: "request-1", message: "backup failed")),
        ])
        XCTAssertThrowsError(try failed.workflow.createBackup(context: failed.context, actions: failed.actions)) { error in
            XCTAssertEqual(error as? RuntimeRedisBackupUseCaseError, .operationFailed("backup failed"))
        }
        XCTAssertTrue(failed.events.contains("status:degraded:redis-backup:backup failed"))

        let unreadable = RedisBackupHarness(results: [.failed("permission denied")])
        XCTAssertThrowsError(try unreadable.workflow.createBackup(context: unreadable.context, actions: unreadable.actions)) { error in
            XCTAssertEqual(
                error as? RuntimeRedisBackupUseCaseError,
                .operationFailed("failed to read redis backup result: permission denied")
            )
        }
        XCTAssertTrue(unreadable.events.contains(
            "status:degraded:redis-backup:failed to read redis backup result: permission denied"
        ))

        let timeout = RedisBackupHarness(results: [.missing, .missing])
        XCTAssertThrowsError(try timeout.workflow.createBackup(context: timeout.context, actions: timeout.actions)) { error in
            XCTAssertEqual(error as? RuntimeRedisBackupUseCaseError, .operationFailed("redis backup timed out"))
        }
        XCTAssertTrue(timeout.events.contains("status:degraded:redis-backup:redis backup timed out"))
    }
}

private final class RedisBackupHarness {
    let workflow = RuntimeRedisBackupWorkflow()
    let context = RuntimeRedisBackupWorkflowContext(
        guestRunDirectory: URL(fileURLWithPath: "/guest/run"),
        redisBackupsDirectory: URL(fileURLWithPath: "/redis/backups"),
        requestFileName: "redis-backup-request.json",
        resultFileName: "redis-backup-result.json",
        waitTimeoutSeconds: 6,
        pollIntervalSeconds: 3
    )
    var events: [String] = []
    var results: [RuntimeRedisBackupResultLoadResult]
    var vmLoaded = false

    lazy var actions = RuntimeRedisBackupWorkflowActions(
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

    init(results: [RuntimeRedisBackupResultLoadResult]) {
        self.results = results
    }
}

private func redisResult(
    status: DatastoreRepairStatus,
    requestId: String?,
    message: String?,
    archive: String? = nil
) -> RedisBackupResultDocument {
    RedisBackupResultDocument(
        requestId: requestId,
        status: status,
        message: message,
        archive: archive
    )
}
