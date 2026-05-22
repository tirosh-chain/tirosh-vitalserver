import RuntimeCore
@testable import HostRuntimeControl
import XCTest

final class RuntimeDatastoreRepairRunnerTests: XCTestCase {
    func testRunRestartsLoadedVMThenRestartsProxyWatchdogAndWritesHealthyStatus() throws {
        let harness = DatastoreRepairHarness()

        try harness.runner.run()

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
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

    func testRunContinuesWhenPreviousResultRemovalFails() throws {
        let harness = DatastoreRepairHarness()
        harness.removeResultError = TestDatastoreRepairError.removeResult

        try harness.runner.run()

        XCTAssertTrue(harness.events.contains("remove-result"))
        XCTAssertTrue(harness.events.contains("request:request-1:2026-05-22T00:00:00Z"))
        XCTAssertEqual(harness.events.last, "log:datastore repair completed")
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
    var removeResultError: Error?
    var waitResultError: Error?

    var runner: RuntimeDatastoreRepairRunner {
        RuntimeDatastoreRepairRunner(
            prepareGuestRunDirectory: {
                self.events.append("prepare-run-dir")
            },
            removePreviousResult: {
                self.events.append("remove-result")
                if let removeResultError = self.removeResultError {
                    throw removeResultError
                }
            },
            writeRequest: { requestID, requestedAt in
                self.events.append("request:\(requestID):\(requestedAt)")
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
            waitForResult: { requestID in
                self.events.append("wait-result:\(requestID)")
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
