import Foundation
import HostInfrastructure
import XCTest

final class InstalledRuntimePathsTests: XCTestCase {
    func testDefaultInstalledPathsMatchHostLayout() {
        let paths = InstalledRuntimePaths.defaultInstalled

        XCTAssertEqual(paths.productRoot.path, "/Library/Application Support/TiroshVitalServer")
        XCTAssertEqual(paths.runtimeHome.path, "/Library/Application Support/TiroshVitalServer/vm")
        XCTAssertEqual(paths.runtimeStatus.path, "/Library/Application Support/TiroshVitalServer/status/runtime-status.json")
        XCTAssertEqual(paths.runtimeUninstallState.path, "/private/tmp/tirosh-vitalserver-uninstall-state.json")
        XCTAssertEqual(paths.hostRunDirectory.path, "/Library/Application Support/TiroshVitalServer/vm/run")
        XCTAssertEqual(paths.guestRunDirectory.path, "/Library/Application Support/TiroshVitalServer/vm/data/run")
        XCTAssertEqual(paths.pidFile.path, "/Library/Application Support/TiroshVitalServer/vm/run/vitalserver-vm.pid")
        XCTAssertEqual(paths.nginxDirectory.path, "/Library/Application Support/TiroshVitalServer/nginx")
        XCTAssertEqual(paths.nginxLogsDirectory.path, "/Library/Application Support/TiroshVitalServer/nginx/logs")
        XCTAssertEqual(paths.nginxExecutable.path, "/Library/Application Support/TiroshVitalServer/nginx/sbin/nginx")
        XCTAssertEqual(paths.productLogsDirectory.path, "/Library/Application Support/TiroshVitalServer/logs")
        XCTAssertEqual(paths.centralRuntimeLogsDirectory.path, "/Library/Application Support/TiroshVitalServer/logs/runtime")
        XCTAssertEqual(paths.proxyNginxAccessLog.path, "/Library/Application Support/TiroshVitalServer/logs/runtime/proxy-nginx.access.log")
        XCTAssertEqual(paths.proxyNginxErrorLog.path, "/Library/Application Support/TiroshVitalServer/logs/runtime/proxy-nginx.error.log")
        XCTAssertEqual(paths.centralGuestLogsDirectory.path, "/Library/Application Support/TiroshVitalServer/logs/guest")
        XCTAssertEqual(paths.guestObservabilityDirectory.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/guest-observability")
        XCTAssertEqual(paths.centralGuestObservabilityDirectory.path, "/Library/Application Support/TiroshVitalServer/logs/guest/guest-observability")
        XCTAssertEqual(paths.logArchiveDirectory.path, "/Library/Application Support/TiroshVitalServer/logs/archive")
        XCTAssertEqual(paths.vmIPFile.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/vm-ip")
        XCTAssertEqual(paths.vmLifecycle.path, "/Library/Application Support/TiroshVitalServer/vm/run/vm-lifecycle.json")
        XCTAssertEqual(paths.runtimeState.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-state.json")
        XCTAssertEqual(paths.bootstrapResult.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/bootstrap-result.json")
        XCTAssertEqual(paths.updateActivationLog.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/activate-update.log")
        XCTAssertEqual(paths.updateActivationResult.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/activate-update-result.json")
        XCTAssertEqual(paths.centralUpdateActivationLog.path, "/Library/Application Support/TiroshVitalServer/logs/guest/activate-update.log")
        XCTAssertEqual(paths.updateShutdownLog.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/prepare-update-shutdown.log")
        XCTAssertEqual(paths.updateShutdownResult.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/prepare-update-shutdown-result.json")
        XCTAssertEqual(paths.centralUpdateShutdownLog.path, "/Library/Application Support/TiroshVitalServer/logs/guest/prepare-update-shutdown.log")
        XCTAssertEqual(paths.datastoreRepairResult.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/repair-datastore-result.json")
        XCTAssertEqual(paths.managerCommandLog.path, "/private/tmp/tirosh-vitalserver-manager-command.log")
        XCTAssertEqual(paths.managerHelperMessageLog.path, "/private/tmp/tirosh-vitalserver-helper-message.log")
        XCTAssertEqual(paths.centralCommandLog.path, "/Library/Application Support/TiroshVitalServer/logs/command.log")
        XCTAssertEqual(paths.guestRuntimeSettings.path, "/Library/Application Support/TiroshVitalServer/vm/data/deploy/runtime-settings.json")
    }

    func testRuntimeHomeInitializerDerivesProductRoot() {
        let paths = InstalledRuntimePaths(runtimeHome: URL(fileURLWithPath: "/tmp/product/vm"))

        XCTAssertEqual(paths.productRoot.path, "/tmp/product")
        XCTAssertEqual(paths.runtimeHome.path, "/tmp/product/vm")
        XCTAssertEqual(paths.backupsDirectory.path, "/tmp/product/backups")
        XCTAssertEqual(paths.runtimeStatus.path, "/tmp/product/status/runtime-status.json")
    }
}
