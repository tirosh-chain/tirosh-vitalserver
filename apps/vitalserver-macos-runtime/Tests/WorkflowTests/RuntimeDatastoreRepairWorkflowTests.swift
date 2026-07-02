import Application
import Contracts
import Workflow
import XCTest
import Errors

final class RuntimeDatastoreRepairWorkflowTests: XCTestCase {
    func testRepairRunsGuestOperationThenRestartsProxyWatchdogAndWritesHealthyStatus() throws {
        let harness = DatastoreRepairHarness()

        try harness.repair()

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "status:recovering:repair-datastore:datastore repair requested",
            "guest-repair",
            "log:datastore repair guest operation completed operationId=datastore-repair-1",
            "restart-proxy",
            "restart-watchdog",
            "wait-health:true:true:true",
            "status:healthy:repair-datastore:datastore repair completed",
            "log:datastore repair completed",
        ])
    }

    func testRepairStartsVMBeforeGuestOperationWhenVMServiceIsNotLoaded() throws {
        let harness = DatastoreRepairHarness()
        harness.vmLoaded = false

        try harness.repair()

        XCTAssertEqual(harness.events.prefix(4), [
            "log:datastore repair requested",
            "status:recovering:repair-datastore:datastore repair requested",
            "start-vm",
            "guest-repair",
        ])
    }

    func testRepairStopsBeforeAftercareWhenGuestOperationFails() {
        let harness = DatastoreRepairHarness()
        harness.guestRepairError = RepairRuntimeUseCaseError.operationFailed("guest datastore repair failed")

        XCTAssertThrowsError(try harness.repair()) { error in
            XCTAssertEqual(error as? RepairRuntimeUseCaseError, .operationFailed("guest datastore repair failed"))
        }

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "status:recovering:repair-datastore:datastore repair requested",
            "guest-repair",
        ])
        XCTAssertFalse(harness.events.contains("restart-proxy"))
        XCTAssertFalse(harness.events.contains("status:healthy:repair-datastore:datastore repair completed"))
    }

    func testRepairStopsBeforeGuestOperationWhenRecoveringStatusWriteFails() {
        let harness = DatastoreRepairHarness()
        harness.statusWriteError = TestDatastoreRepairError.statusWrite

        XCTAssertThrowsError(try harness.repair()) { error in
            XCTAssertEqual(error as? TestDatastoreRepairError, .statusWrite)
        }

        XCTAssertEqual(harness.events, [
            "log:datastore repair requested",
            "status:recovering:repair-datastore:datastore repair requested",
        ])
    }
}

private final class DatastoreRepairHarness {
    var events: [String] = []
    var vmLoaded = true
    var guestRepairError: Error?
    var statusWriteError: Error?

    func repair() throws {
        try RuntimeDatastoreRepairWorkflow().repair(
            context: RunDatastoreRepairContext(),
            operations: operations
        )
    }

    var operations: RunDatastoreRepairOperations {
        RunDatastoreRepairOperations(
            isVMServiceLoaded: {
                self.vmLoaded
            },
            startVMService: {
                self.events.append("start-vm")
            },
            runGuestDatastoreRepair: {
                self.events.append("guest-repair")
                if let guestRepairError = self.guestRepairError {
                    throw guestRepairError
                }
                return RuntimeGuestControlServiceOperation(
                    operationId: "datastore-repair-1",
                    service: "datastore-repair",
                    command: .repairDatastore,
                    state: .completed,
                    createdAt: "2026-07-01T00:00:00+00:00",
                    updatedAt: "2026-07-01T00:00:01+00:00"
                )
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
                if let statusWriteError = self.statusWriteError {
                    throw statusWriteError
                }
            },
            log: { message in
                self.events.append("log:\(message)")
            }
        )
    }
}

private enum TestDatastoreRepairError: Error, Equatable {
    case statusWrite
}
