import Contracts
import XCTest

final class RuntimeFileNamesTests: XCTestCase {
    func testRuntimeFileNamesRemainStableForHostAndGuestContracts() {
        XCTAssertEqual(RuntimeFileNames.runtimeStatus, "runtime-status.json")
        XCTAssertEqual(RuntimeFileNames.runtimeEvents, "runtime-events.jsonl")
        XCTAssertEqual(RuntimeFileNames.runtimeObservabilityDB, "runtime-observability.sqlite")
        XCTAssertEqual(RuntimeFileNames.vmIP, "vm-ip")
        XCTAssertEqual(RuntimeFileNames.runtimeState, "runtime-state.json")
        XCTAssertEqual(RuntimeFileNames.bootstrapLog, "bootstrap.log")
        XCTAssertEqual(RuntimeFileNames.bootstrapResult, "bootstrap-result.json")
        XCTAssertEqual(RuntimeFileNames.datastoreRepairRequest, "repair-datastore.request")
        XCTAssertEqual(RuntimeFileNames.datastoreRepairResult, "repair-datastore-result.json")
        XCTAssertEqual(RuntimeFileNames.datastoreRepairLog, "repair-datastore.log")
        XCTAssertEqual(RuntimeFileNames.updateActivationRequest, "activate-update.request")
        XCTAssertEqual(RuntimeFileNames.updateActivationResult, "activate-update-result.json")
        XCTAssertEqual(RuntimeFileNames.updateActivationLog, "activate-update.log")
        XCTAssertEqual(RuntimeFileNames.managerCommandLog, "tirosh-vitalserver-manager-command.log")
    }
}
