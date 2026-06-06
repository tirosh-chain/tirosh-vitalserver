import Contracts
import Workflow
import XCTest

final class RuntimeDatastoreRepairRunnerTests: XCTestCase {
    func testRunRestartsLoadedVMThenRestartsProxyWatchdogAndWritesHealthyStatus() throws {
        let harness = DatastoreRepairHarness()

        try harness.runner.run()

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "capability",
            "prepare-run-dir",
            "remove-result",
            "status:recovering:repair-datastore:datastore repair requested",
            "request:request-1:2026-05-22T00:00:00Z",
            "restart-vm",
            "wait-result:request-1",
            "restart-proxy",
            "restart-watchdog",
            "wait-health:true:true:true",
            "status:healthy:repair-datastore:datastore repair completed",
            "log:datastore repair completed",
        ])
    }

    func testRunStartsVMWhenVMServiceIsNotLoaded() throws {
        let harness = DatastoreRepairHarness()
        harness.vmLoaded = false

        try harness.runner.run()

        XCTAssertTrue(harness.events.contains("start-vm"))
        XCTAssertFalse(harness.events.contains("restart-vm"))
    }

    func testRunStopsWhenPreviousResultRemovalFails() {
        let harness = DatastoreRepairHarness()
        harness.removeResultError = TestDatastoreRepairError.removeResult

        XCTAssertThrowsError(try harness.runner.run())

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "capability",
            "prepare-run-dir",
            "remove-result",
        ])
    }

    func testRunStopsBeforeWritingRequestWhenCapabilityIsMissing() {
        let harness = DatastoreRepairHarness()
        harness.capabilityError = RuntimeDatastoreRepairWorkflowError.operationFailed("guest capability missing: repair-datastore")

        XCTAssertThrowsError(try harness.runner.run()) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: repair-datastore")
        }

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "capability",
        ])
    }

    func testRunStopsBeforeHealthyStatusWhenResultWaitFails() {
        let harness = DatastoreRepairHarness()
        harness.waitResultError = TestDatastoreRepairError.waitResult

        XCTAssertThrowsError(try harness.runner.run())

        XCTAssertTrue(harness.events.contains("wait-result:request-1"))
        XCTAssertFalse(harness.events.contains("restart-proxy"))
        XCTAssertFalse(harness.events.contains("status:healthy:repair-datastore:datastore repair completed"))
    }
}

private final class DatastoreRepairHarness {
    var events: [String] = []
    var vmLoaded = true
    var capabilityError: Error?
    var removeResultError: Error?
    var waitResultError: Error?

    var runner: RuntimeDatastoreRepairRunner {
        RuntimeDatastoreRepairRunner(
            requireCapability: {
                self.events.append("capability")
                if let capabilityError = self.capabilityError {
                    throw capabilityError
                }
            },
            prepareGuestRunDirectory: {
                self.events.append("prepare-run-dir")
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
            waitForResult: { request in
                self.events.append("wait-result:\(request.id)")
                if let waitResultError = self.waitResultError {
                    throw waitResultError
                }
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
            makeRequestID: {
                "request-1"
            },
            timestamp: {
                "2026-05-22T00:00:00Z"
            },
            log: { message in
                self.events.append("log:\(message)")
            }
        )
    }
}

private enum TestDatastoreRepairError: Error {
    case removeResult
    case waitResult
}
