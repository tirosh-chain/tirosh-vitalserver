import Contracts
import XCTest
import Errors

final class RuntimeFileNameContractsTests: XCTestCase {
    func testRuntimePackageArtifactFileNamesRemainStableForPackageAndUpdateArtifacts() {
        XCTAssertEqual(RuntimePackageArtifactFileNames.rootfsBase, "rootfs-base.raw.gz")
        XCTAssertEqual(RuntimePackageArtifactFileNames.runtimeVersion, "runtime-version.json")
        XCTAssertEqual(RuntimePackageArtifactFileNames.backupManifest, "backup-manifest.json")
        XCTAssertEqual(RuntimePackageArtifactFileNames.updateBundleManifest, "manifest.json")
    }

    func testRuntimeHostContractFileNamesRemainStableForHostProvidedContracts() {
        XCTAssertEqual(RuntimeHostContractFileNames.appliedVMConfig, "applied-vm-config.json")
        XCTAssertEqual(RuntimeHostContractFileNames.hostTime, "host-time.json")
    }

    func testRuntimeWorkflowArtifactFileNamesRemainStableForDiagnosticsArtifacts() {
        XCTAssertEqual(RuntimeWorkflowArtifactFileNames.runtimeInstallState, "tirosh-vitalserver-install-state.json")
    }

    func testRuntimeLogArtifactFileNamesRemainStableForDiagnosticsLogs() {
        XCTAssertEqual(RuntimeLogArtifactFileNames.bootstrapLog, "bootstrap.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.datastoreRepairLog, "repair-datastore.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.redisBackupLog, "redis-backup.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.redisRestoreLog, "redis-restore.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.updateActivationLog, "activate-update.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.updateShutdownLog, "prepare-update-shutdown.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.containerLogs, "container-logs.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.managerCommandLog, "tirosh-vitalserver-manager-command.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.managerHelperMessageLog, "tirosh-vitalserver-helper-message.log")
        XCTAssertEqual(RuntimeLogArtifactFileNames.runtimeUninstallLog, "tirosh-vitalserver-uninstall.log")
    }

    func testRuntimeDiagnosticsArtifactFileNamesRemainStableForDiagnosticsAndExportArtifacts() {
        XCTAssertEqual(RuntimeDiagnosticsArtifactFileNames.runtimeStatus, "runtime-status.json")
        XCTAssertEqual(RuntimeDiagnosticsArtifactFileNames.runtimeProgress, "runtime-progress.json")
        XCTAssertEqual(RuntimeDiagnosticsArtifactFileNames.runtimeEvents, "runtime-events.jsonl")
        XCTAssertEqual(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB, "runtime-observability.sqlite")
        XCTAssertEqual(RuntimeDiagnosticsArtifactFileNames.runtimeObservation, "runtime-observation.json")
        XCTAssertEqual(RuntimeDiagnosticsArtifactFileNames.bootstrapResult, "bootstrap-result.json")
    }

    func testRuntimeBootstrapEvidenceFileNamesRemainStableForCompatibilityEvidence() {
        XCTAssertEqual(RuntimeBootstrapEvidenceFileNames.vmIP, "vm-ip")
    }

    func testRuntimeLegacyHostStateFileNameRemainsStableForExplicitMigrationOnly() {
        XCTAssertEqual(RuntimeLegacyHostStateFileNames.operationLease, "runtime-operation-lease.json")
    }
}
