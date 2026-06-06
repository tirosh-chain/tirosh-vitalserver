import Application
import Contracts
import Domain
import XCTest
import Errors

final class RunDatastoreRepairUseCaseTests: XCTestCase {
    func testRepairRestartsLoadedVMThenRestartsProxyWatchdogAndWritesHealthyStatus() throws {
        let harness = DatastoreRepairHarness()

        try harness.repair()

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "capability",
            "create-dir:/guest/run:true",
            "remove-result",
            "status:recovering:repair-datastore:datastore repair requested",
            "request:request-1:2026-05-22T00:00:00Z",
            "restart-vm",
            "log:waiting for datastore repair result timeoutSeconds=300.0",
            "log:datastore repair guest result completed message=done",
            "restart-proxy",
            "restart-watchdog",
            "wait-health:true:true:true",
            "status:healthy:repair-datastore:datastore repair completed",
            "log:datastore repair completed",
        ])
    }

    func testRepairStartsVMWhenVMServiceIsNotLoaded() throws {
        let harness = DatastoreRepairHarness()
        harness.vmLoaded = false

        try harness.repair()

        XCTAssertTrue(harness.events.contains("start-vm"))
        XCTAssertFalse(harness.events.contains("restart-vm"))
    }

    func testRepairStopsWhenPreviousResultRemovalFails() {
        let harness = DatastoreRepairHarness()
        harness.removeResultError = TestDatastoreRepairError.removeResult

        XCTAssertThrowsError(try harness.repair())

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "capability",
            "create-dir:/guest/run:true",
            "remove-result",
        ])
    }

    func testRepairStopsBeforeWritingRequestWhenCapabilityIsMissing() {
        let harness = DatastoreRepairHarness()
        harness.capabilityError = RepairRuntimeUseCaseError.operationFailed("guest capability missing: repair-datastore")

        XCTAssertThrowsError(try harness.repair()) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: repair-datastore")
        }

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "capability",
        ])
    }

    func testRepairStopsBeforeHealthyStatusWhenResultWaitFails() {
        let harness = DatastoreRepairHarness(results: [
            .loaded(result(status: .failed, requestId: "request-1", message: "repair failed")),
        ])

        XCTAssertThrowsError(try harness.repair()) { error in
            XCTAssertEqual(String(describing: error), "runtime health check failed")
        }

        XCTAssertTrue(harness.events.contains("log:datastore repair guest result failed message=repair failed"))
        XCTAssertFalse(harness.events.contains("restart-proxy"))
        XCTAssertFalse(harness.events.contains("status:healthy:repair-datastore:datastore repair completed"))
    }

    func testRepairWaitPollsUntilGuestReportsCompleted() throws {
        let harness = DatastoreRepairHarness(results: [
            .missing,
            .loaded(result(status: .running, requestId: "request-1", message: "repairing")),
            .loaded(result(status: .completed, requestId: "request-1", message: "done")),
        ])

        try harness.repair()

        XCTAssertTrue(harness.events.contains("sleep"))
        XCTAssertTrue(harness.events.contains("status-best-effort:recovering:repair-datastore:waiting for datastore repair guest worker"))
        XCTAssertTrue(harness.events.contains("log:datastore repair guest result completed message=done"))
    }
}

private final class DatastoreRepairHarness {
    var events: [String] = []
    var vmLoaded = true
    var capabilityError: Error?
    var removeResultError: Error?
    var results: [RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>]

    init(results: [RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>] = [
        .loaded(result(status: .completed, requestId: "request-1", message: "done")),
    ]) {
        self.results = results
    }

    func repair() throws {
        try RunDatastoreRepairUseCase().repair(
            context: RunDatastoreRepairContext(
                guestRunDirectory: URL(fileURLWithPath: "/guest/run"),
                waitTimeoutSeconds: 300
            ),
            operations: operations
        )
    }

    var operations: RunDatastoreRepairOperations {
        RunDatastoreRepairOperations(
            requireCapability: {
                self.events.append("capability")
                if let capabilityError = self.capabilityError {
                    throw capabilityError
                }
            },
            createDirectory: { url, withIntermediateDirectories in
                self.events.append("create-dir:\(url.path):\(withIntermediateDirectories)")
            },
            removePreviousResult: {
                self.events.append("remove-result")
                if let removeResultError = self.removeResultError {
                    throw removeResultError
                }
            },
            writeRequest: { request in
                self.events.append("request:\(request.id):\(request.requestedAt)")
            },
            isVMServiceLoaded: {
                self.vmLoaded
            },
            startVMService: {
                self.events.append("start-vm")
            },
            restartVMService: {
                self.events.append("restart-vm")
            },
            loadResult: {
                if self.results.count > 1 {
                    return self.results.removeFirst()
                }
                return self.results[0]
            },
            restartProxyService: {
                self.events.append("restart-proxy")
            },
            restartWatchdogService: {
                self.events.append("restart-watchdog")
            },
            waitForHealth: { policy in
                self.events.append("wait-health:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
            },
            writeStatus: { status, operation, message in
                self.events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            writeStatusBestEffort: { status, operation, message in
                self.events.append("status-best-effort:\(status.rawValue):\(operation.rawValue):\(message)")
            },
            requestID: {
                "request-1"
            },
            timestamp: {
                "2026-05-22T00:00:00Z"
            },
            sleep: {
                self.events.append("sleep")
            },
            log: { message in
                self.events.append("log:\(message)")
            }
        )
    }
}

private func result(
    status: DatastoreRepairStatus,
    requestId: String,
    message: String
) -> DatastoreRepairResultDocument {
    DatastoreRepairResultDocument(
        schemaVersion: 1,
        requestId: requestId,
        operation: .repairDatastore,
        status: status,
        message: message,
        updatedAt: "2026-05-22T00:00:00Z"
    )
}

private enum TestDatastoreRepairError: Error {
    case removeResult
}
