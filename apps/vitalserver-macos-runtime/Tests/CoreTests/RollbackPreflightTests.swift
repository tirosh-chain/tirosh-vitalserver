import Foundation
import Core
import Contracts
import XCTest

final class RollbackPreflightTests: XCTestCase {
    func testContextCarriesBackupInputsAndRestartPolicy() {
        let context = RollbackPreflightContext(
            backup: URL(fileURLWithPath: "/tmp/backups/backup-1"),
            backupRootfs: URL(fileURLWithPath: "/tmp/backups/backup-1/rootfs-base.raw.gz"),
            backupVersion: URL(fileURLWithPath: "/tmp/backups/backup-1/runtime-version.json"),
            restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartProxy: true,
                restartWatchdog: false
            )
        )

        XCTAssertEqual(context.backup.lastPathComponent, "backup-1")
        XCTAssertEqual(context.backupRootfs.lastPathComponent, "rootfs-base.raw.gz")
        XCTAssertTrue(context.restartPolicy.restartVM)
        XCTAssertTrue(context.restartPolicy.restartProxy)
        XCTAssertFalse(context.restartPolicy.restartWatchdog)
    }
}
