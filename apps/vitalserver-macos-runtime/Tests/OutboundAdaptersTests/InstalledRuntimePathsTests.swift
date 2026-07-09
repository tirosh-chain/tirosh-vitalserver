import Foundation
import OutboundAdapters
import XCTest
import Errors

final class InstalledRuntimePathsTests: XCTestCase {
    func testDefaultInstalledPathsMatchHostLayout() {
        let paths = InstalledRuntimePaths.defaultInstalled

        XCTAssertEqual(paths.productRoot.path, "/Library/Application Support/VitalServerHelper")
        XCTAssertEqual(paths.runtimeHome.path, "/Library/Application Support/VitalServerHelper/vm")
        XCTAssertEqual(paths.runtimeStatus.path, "/Library/Application Support/VitalServerHelper/status/runtime-status.json")
        XCTAssertEqual(paths.runtimeInstallState.path, "/private/tmp/tirosh-vitalserver-install-state.json")
        XCTAssertEqual(paths.runtimeUninstallState.path, "/private/tmp/tirosh-vitalserver-uninstall-state.json")
        XCTAssertEqual(paths.hostRunDirectory.path, "/Library/Application Support/VitalServerHelper/vm/run")
        XCTAssertEqual(paths.guestRunDirectory.path, "/Library/Application Support/VitalServerHelper/vm/data/run")
        XCTAssertEqual(paths.pidFile.path, "/Library/Application Support/VitalServerHelper/vm/run/vitalserver-vm.pid")
        XCTAssertEqual(paths.nginxDirectory.path, "/Library/Application Support/VitalServerHelper/nginx")
        XCTAssertEqual(paths.nginxLogsDirectory.path, "/Library/Application Support/VitalServerHelper/nginx/logs")
        XCTAssertEqual(paths.nginxExecutable.path, "/Library/Application Support/VitalServerHelper/nginx/sbin/nginx")
        XCTAssertEqual(paths.productLogsDirectory.path, "/Library/Application Support/VitalServerHelper/logs")
        XCTAssertEqual(paths.centralRuntimeLogsDirectory.path, "/Library/Application Support/VitalServerHelper/logs/runtime")
        XCTAssertEqual(paths.proxyNginxAccessLog.path, "/Library/Application Support/VitalServerHelper/logs/runtime/proxy-nginx.access.log")
        XCTAssertEqual(paths.proxyNginxErrorLog.path, "/Library/Application Support/VitalServerHelper/logs/runtime/proxy-nginx.error.log")
        XCTAssertEqual(paths.centralGuestLogsDirectory.path, "/Library/Application Support/VitalServerHelper/logs/guest")
        XCTAssertEqual(paths.guestObservabilityDirectory.path, "/Library/Application Support/VitalServerHelper/vm/data/run/guest-observability")
        XCTAssertEqual(paths.centralGuestObservabilityDirectory.path, "/Library/Application Support/VitalServerHelper/logs/guest/guest-observability")
        XCTAssertEqual(paths.logArchiveDirectory.path, "/Library/Application Support/VitalServerHelper/logs/archive")
        XCTAssertEqual(paths.vmIPFile.path, "/Library/Application Support/VitalServerHelper/vm/data/run/vm-ip")
        XCTAssertEqual(paths.vmLifecycle.path, "/Library/Application Support/VitalServerHelper/vm/run/vm-lifecycle.json")
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
    }

    func testRuntimeHomeInitializerDerivesProductRoot() {
        let paths = InstalledRuntimePaths(runtimeHome: URL(fileURLWithPath: "/tmp/product/vm"))

        XCTAssertEqual(paths.productRoot.path, "/tmp/product")
        XCTAssertEqual(paths.runtimeHome.path, "/tmp/product/vm")
        XCTAssertEqual(paths.backupsDirectory.path, "/tmp/product/backups")
        XCTAssertEqual(paths.runtimeStatus.path, "/tmp/product/status/runtime-status.json")
    }
}
