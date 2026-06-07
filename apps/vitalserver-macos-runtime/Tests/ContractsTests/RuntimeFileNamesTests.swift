import Contracts
import XCTest
import Errors

final class RuntimeFileNamesTests: XCTestCase {
    func testRuntimeFileNamesRemainStableForHostAndGuestContracts() {
        XCTAssertEqual(RuntimeFileNames.runtimeStatus, "runtime-status.json")
        XCTAssertEqual(RuntimeFileNames.runtimeEvents, "runtime-events.jsonl")
        XCTAssertEqual(RuntimeFileNames.runtimeObservabilityDB, "runtime-observability.sqlite")
        XCTAssertEqual(RuntimeFileNames.runtimeInstallState, "tirosh-vitalserver-install-state.json")
        XCTAssertEqual(RuntimeFileNames.runtimeUninstallState, "tirosh-vitalserver-uninstall-state.json")
        XCTAssertEqual(RuntimeFileNames.vmIP, "vm-ip")
        XCTAssertEqual(RuntimeFileNames.vmLifecycle, "vm-lifecycle.json")
        XCTAssertEqual(RuntimeFileNames.runtimeState, "runtime-state.json")
        XCTAssertEqual(RuntimeFileNames.bootstrapLog, "bootstrap.log")
        XCTAssertEqual(RuntimeFileNames.bootstrapResult, "bootstrap-result.json")
        XCTAssertEqual(RuntimeFileNames.datastoreRepairRequest, "repair-datastore.request")
        XCTAssertEqual(RuntimeFileNames.datastoreRepairResult, "repair-datastore-result.json")
        XCTAssertEqual(RuntimeFileNames.datastoreRepairLog, "repair-datastore.log")
        XCTAssertEqual(RuntimeFileNames.redisBackupRequest, "redis-backup.request")
        XCTAssertEqual(RuntimeFileNames.redisBackupResult, "redis-backup-result.json")
        XCTAssertEqual(RuntimeFileNames.redisBackupLog, "redis-backup.log")
        XCTAssertEqual(RuntimeFileNames.updateActivationRequest, "activate-update.request")
        XCTAssertEqual(RuntimeFileNames.updateActivationResult, "activate-update-result.json")
        XCTAssertEqual(RuntimeFileNames.updateActivationLog, "activate-update.log")
        XCTAssertEqual(RuntimeFileNames.updateShutdownRequest, "prepare-update-shutdown.request")
        XCTAssertEqual(RuntimeFileNames.updateShutdownResult, "prepare-update-shutdown-result.json")
        XCTAssertEqual(RuntimeFileNames.updateShutdownLog, "prepare-update-shutdown.log")
        XCTAssertEqual(RuntimeFileNames.containerLogs, "container-logs.log")
        XCTAssertEqual(RuntimeFileNames.managerCommandLog, "tirosh-vitalserver-manager-command.log")
        XCTAssertEqual(RuntimeFileNames.managerHelperMessageLog, "tirosh-vitalserver-helper-message.log")
    }
}
