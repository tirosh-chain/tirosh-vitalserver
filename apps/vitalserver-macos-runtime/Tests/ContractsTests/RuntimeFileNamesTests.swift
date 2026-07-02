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
        XCTAssertEqual(RuntimeFileNames.appliedVMConfig, "applied-vm-config.json")
        XCTAssertEqual(RuntimeFileNames.runtimeState, "runtime-state.json")
        XCTAssertEqual(RuntimeFileNames.bootstrapLog, "bootstrap.log")
        XCTAssertEqual(RuntimeFileNames.bootstrapResult, "bootstrap-result.json")
        XCTAssertEqual(RuntimeFileNames.datastoreRepairLog, "repair-datastore.log")
        XCTAssertEqual(RuntimeFileNames.redisBackupLog, "redis-backup.log")
        XCTAssertEqual(RuntimeFileNames.redisRestoreLog, "redis-restore.log")
        XCTAssertEqual(RuntimeFileNames.updateActivationLog, "activate-update.log")
        XCTAssertEqual(RuntimeFileNames.updateShutdownLog, "prepare-update-shutdown.log")
        XCTAssertEqual(RuntimeFileNames.containerLogs, "container-logs.log")
        XCTAssertEqual(RuntimeFileNames.managerCommandLog, "tirosh-vitalserver-manager-command.log")
        XCTAssertEqual(RuntimeFileNames.managerHelperMessageLog, "tirosh-vitalserver-helper-message.log")
    }
}
