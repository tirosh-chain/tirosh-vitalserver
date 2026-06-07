import Contracts
import Foundation
import XCTest

final class RuntimeManagedBackupPolicyTests: XCTestCase {
    func testManagedBackupMustBeInsideBackupRootAndUseBackupNameConvention() {
        let root = URL(fileURLWithPath: "/product/backups")

        XCTAssertTrue(RuntimeManagedBackupPolicy.isManagedBackupURL(
            URL(fileURLWithPath: "/product/backups/20260522T000000Z-before-0.1.3"),
            backupsRoot: root
        ))
        XCTAssertFalse(RuntimeManagedBackupPolicy.isManagedBackupURL(
            URL(fileURLWithPath: "/product/backups/manual-copy"),
            backupsRoot: root
        ))
        XCTAssertFalse(RuntimeManagedBackupPolicy.isManagedBackupURL(
            URL(fileURLWithPath: "/tmp/20260522T000000Z-before-0.1.3"),
            backupsRoot: root
        ))
    }
}
