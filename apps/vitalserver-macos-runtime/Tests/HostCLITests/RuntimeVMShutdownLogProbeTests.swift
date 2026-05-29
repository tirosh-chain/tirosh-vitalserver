import Foundation
@testable import HostCLI
import XCTest

final class RuntimeVMShutdownLogProbeTests: XCTestCase {
    func testDetectsDiskSafeShutdownMarkerAfterWatermark() {
        let previousRun = "All filesystems unmounted.\n"
        let currentRun = """
        Reached target poweroff.target - System Power Off.
        All filesystems, swaps, loop devices, MD devices and DM devices detached.
        """
        let data = Data((previousRun + currentRun).utf8)

        XCTAssertTrue(RuntimeVMShutdownLogProbe.diskSafeShutdownReached(
            in: data,
            after: UInt64(previousRun.utf8.count)
        ))
    }

    func testIgnoresDiskSafeShutdownMarkerBeforeWatermark() {
        let previousRun = "All filesystems unmounted.\n"
        let currentRun = "Waiting for process: 712 (systemd-network)\n"
        let data = Data((previousRun + currentRun).utf8)

        XCTAssertFalse(RuntimeVMShutdownLogProbe.diskSafeShutdownReached(
            in: data,
            after: UInt64(previousRun.utf8.count)
        ))
    }
}
