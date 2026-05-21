import Foundation
import RuntimeCore
import XCTest

final class InstalledRuntimePathsTests: XCTestCase {
    func testDefaultInstalledPathsMatchHostLayout() {
        let paths = InstalledRuntimePaths.defaultInstalled

        XCTAssertEqual(paths.productRoot.path, "/Library/Application Support/TiroshVitalServer")
        XCTAssertEqual(paths.runtimeHome.path, "/Library/Application Support/TiroshVitalServer/vm")
        XCTAssertEqual(paths.runtimeStatus.path, "/Library/Application Support/TiroshVitalServer/status/runtime-status.json")
        XCTAssertEqual(paths.hostRunDirectory.path, "/Library/Application Support/TiroshVitalServer/vm/run")
        XCTAssertEqual(paths.guestRunDirectory.path, "/Library/Application Support/TiroshVitalServer/vm/data/run")
        XCTAssertEqual(paths.pidFile.path, "/Library/Application Support/TiroshVitalServer/vm/run/vitalserver-vm.pid")
        XCTAssertEqual(paths.nginxDirectory.path, "/Library/Application Support/TiroshVitalServer/nginx")
        XCTAssertEqual(paths.nginxLogsDirectory.path, "/Library/Application Support/TiroshVitalServer/nginx/logs")
        XCTAssertEqual(paths.nginxExecutable.path, "/Library/Application Support/TiroshVitalServer/nginx/sbin/nginx")
        XCTAssertEqual(paths.vmIPFile.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/vm-ip")
        XCTAssertEqual(paths.runtimeState.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/runtime-state.json")
        XCTAssertEqual(paths.updateActivationLog.path, "/Library/Application Support/TiroshVitalServer/vm/data/run/activate-update.log")
        XCTAssertEqual(paths.managerCommandLog.path, "/private/tmp/tirosh-vitalserver-manager-command.log")
    }

    func testRuntimeHomeInitializerDerivesProductRoot() {
        let paths = InstalledRuntimePaths(runtimeHome: URL(fileURLWithPath: "/tmp/product/vm"))

        XCTAssertEqual(paths.productRoot.path, "/tmp/product")
        XCTAssertEqual(paths.runtimeHome.path, "/tmp/product/vm")
        XCTAssertEqual(paths.backupsDirectory.path, "/tmp/product/backups")
        XCTAssertEqual(paths.runtimeStatus.path, "/tmp/product/status/runtime-status.json")
    }
}
