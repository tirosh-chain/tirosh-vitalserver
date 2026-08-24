import Foundation
import OutboundAdapters
import XCTest
import Errors

final class InstalledRuntimePathsTests: XCTestCase {
    func testDefaultInstalledPathsMatchHostLayout() {
        let paths = InstalledRuntimePaths.defaultInstalled

        XCTAssertEqual(paths.productRoot.path, "/Library/Application Support/VitalServerHelper")
        XCTAssertEqual(paths.runtimeHome.path, "/Library/Application Support/VitalServerHelper/vm")
        XCTAssertEqual(paths.runtimeStateDatabase.path, "/Library/Application Support/VitalServerHelper/vm/runtime/runtime-state.sqlite")
        XCTAssertEqual(paths.runtimeObservabilityDB.path, "/Library/Application Support/VitalServerHelper/status/runtime-observability.sqlite")
        XCTAssertNotEqual(paths.runtimeStateDatabase, paths.runtimeObservabilityDB)
        XCTAssertEqual(paths.runtimeStatus.path, "/Library/Application Support/VitalServerHelper/status/runtime-status.json")
        XCTAssertEqual(paths.runtimeInstallState.path, "/private/tmp/tirosh-vitalserver-install-state.json")
        XCTAssertEqual(paths.hostRunDirectory.path, "/Library/Application Support/VitalServerHelper/vm/run")
        XCTAssertEqual(paths.guestRunDirectory.path, "/Library/Application Support/VitalServerHelper/vm/data/run")
        XCTAssertEqual(paths.pidFile.path, "/Library/Application Support/VitalServerHelper/vm/run/vitalserver-vm.pid")
        XCTAssertEqual(
            paths.hostPlatformCurrentRelease.path,
            "/Library/Application Support/VitalServerHelper/host-platform/current"
        )
        XCTAssertEqual(paths.nginxDirectory.path, "/Library/Application Support/VitalServerHelper/nginx")
        XCTAssertEqual(paths.nginxLogsDirectory.path, "/Library/Application Support/VitalServerHelper/nginx/logs")
        XCTAssertEqual(
            paths.nginxExecutable.path,
            "/Library/Application Support/VitalServerHelper/host-platform/current/nginx/sbin/nginx"
        )
        XCTAssertEqual(paths.productLogsDirectory.path, "/Library/Application Support/VitalServerHelper/logs")
        XCTAssertEqual(paths.centralRuntimeLogsDirectory.path, "/Library/Application Support/VitalServerHelper/logs/runtime")
        XCTAssertEqual(paths.proxyNginxAccessLog.path, "/Library/Application Support/VitalServerHelper/logs/runtime/proxy-nginx.access.log")
        XCTAssertEqual(paths.proxyNginxErrorLog.path, "/Library/Application Support/VitalServerHelper/logs/runtime/proxy-nginx.error.log")
        XCTAssertEqual(paths.centralGuestLogsDirectory.path, "/Library/Application Support/VitalServerHelper/logs/guest")
        XCTAssertEqual(paths.guestObservabilityDirectory.path, "/Library/Application Support/VitalServerHelper/vm/data/run/guest-observability")
        XCTAssertEqual(paths.centralGuestObservabilityDirectory.path, "/Library/Application Support/VitalServerHelper/logs/guest/guest-observability")
        XCTAssertEqual(paths.logArchiveDirectory.path, "/Library/Application Support/VitalServerHelper/logs/archive")
        XCTAssertEqual(paths.vmIPFile.path, "/Library/Application Support/VitalServerHelper/vm/data/run/vm-ip")
        XCTAssertEqual(paths.runtimeObservation.path, "/Library/Application Support/VitalServerHelper/vm/data/run/runtime-observation.json")
        XCTAssertEqual(paths.bootstrapResult.path, "/Library/Application Support/VitalServerHelper/vm/data/run/bootstrap-result.json")
        XCTAssertEqual(paths.updateActivationLog.path, "/Library/Application Support/VitalServerHelper/vm/data/run/activate-update.log")
        XCTAssertEqual(paths.centralUpdateActivationLog.path, "/Library/Application Support/VitalServerHelper/logs/guest/activate-update.log")
        XCTAssertEqual(paths.updateShutdownLog.path, "/Library/Application Support/VitalServerHelper/vm/data/run/prepare-update-shutdown.log")
        XCTAssertEqual(paths.centralUpdateShutdownLog.path, "/Library/Application Support/VitalServerHelper/logs/guest/prepare-update-shutdown.log")
        XCTAssertEqual(paths.managerCommandLog.path, "/private/tmp/tirosh-vitalserver-manager-command.log")
        XCTAssertEqual(paths.managerHelperMessageLog.path, "/private/tmp/tirosh-vitalserver-helper-message.log")
        XCTAssertEqual(paths.centralCommandLog.path, "/Library/Application Support/VitalServerHelper/logs/command.log")
        XCTAssertEqual(paths.guestRuntimeSettings.path, "/Library/Application Support/VitalServerHelper/vm/data/deploy/runtime-settings.json")
        XCTAssertEqual(
            paths.updateBootstrapTrustStore.path,
            "/Library/Application Support/VitalServerHelper/config/update-bootstrap-trust-store.json"
        )
        XCTAssertEqual(
            paths.updateBootstrapStagingDirectory.path,
            "/Library/Application Support/VitalServerHelper/update-bootstrap"
        )
        XCTAssertEqual(
            paths.updateBootstrapVerificationDirectory.path,
            "/Library/Application Support/VitalServerHelper/update-bootstrap-verification"
        )
        XCTAssertEqual(
            paths.updateBootstrapVerificationReceipt(updateId: "update-42").path,
            "/Library/Application Support/VitalServerHelper/update-bootstrap-verification/update-42.json"
        )
        XCTAssertEqual(
            paths.standardUninstallRetainedDataRoot.path,
            "/Library/Application Support/VitalServerHelper-retained-uninstall-data"
        )
        XCTAssertEqual(
            paths.helperManagedDefaultVitalFilesDirectory.path,
            "/Users/Shared/VitalServerHelper/vital-files"
        )
    }

    func testRuntimeHomeInitializerDerivesProductRoot() {
        let paths = InstalledRuntimePaths(runtimeHome: URL(fileURLWithPath: "/tmp/product/vm"))

        XCTAssertEqual(paths.productRoot.path, "/tmp/product")
        XCTAssertEqual(paths.runtimeHome.path, "/tmp/product/vm")
        XCTAssertEqual(paths.backupsDirectory.path, "/tmp/product/backups")
        XCTAssertEqual(paths.runtimeStatus.path, "/tmp/product/status/runtime-status.json")
        XCTAssertEqual(
            paths.updateBootstrapTrustStore.path,
            "/tmp/product/config/update-bootstrap-trust-store.json"
        )
        XCTAssertEqual(
            paths.updateBootstrapStagingDirectory.path,
            "/tmp/product/update-bootstrap"
        )
        XCTAssertEqual(
            paths.updateBootstrapVerificationDirectory.path,
            "/tmp/product/update-bootstrap-verification"
        )
        XCTAssertEqual(
            paths.updateBootstrapVerificationReceipt(updateId: "update-42").path,
            "/tmp/product/update-bootstrap-verification/update-42.json"
        )
        XCTAssertEqual(
            paths.standardUninstallRetainedDataRoot.path,
            "/tmp/product-retained-uninstall-data"
        )
    }
}
