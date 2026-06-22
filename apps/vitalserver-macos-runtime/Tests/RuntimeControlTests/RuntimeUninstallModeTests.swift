import RuntimeControl
import XCTest

final class RuntimeUninstallModeTests: XCTestCase {
    func testModeSeparatesCleanFromForceCleanUninstaller() {
        XCTAssertEqual(RuntimeUninstallMode.standard.rawValue, "standard")
        XCTAssertEqual(RuntimeUninstallMode.clean.rawValue, "clean")
        XCTAssertEqual(RuntimeUninstallMode.forceCleanUninstaller.rawValue, "forceCleanUninstaller")

        XCTAssertFalse(RuntimeUninstallMode.standard.clean)
        XCTAssertFalse(RuntimeUninstallMode.standard.forceClean)

        XCTAssertTrue(RuntimeUninstallMode.clean.clean)
        XCTAssertFalse(RuntimeUninstallMode.clean.forceClean)

        XCTAssertTrue(RuntimeUninstallMode.forceCleanUninstaller.clean)
        XCTAssertTrue(RuntimeUninstallMode.forceCleanUninstaller.forceClean)
    }
}
