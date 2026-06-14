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

    func testRuntimeDataBackupMustBeDirectChildInsideRuntimeDataBackupRoot() {
        let root = URL(fileURLWithPath: "/product/backups/vitalserver-helper")

        XCTAssertTrue(RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(
            URL(fileURLWithPath: "/product/backups/vitalserver-helper/20260613T000000Z-manual"),
            runtimeDataBackupsRoot: root
        ))
        XCTAssertFalse(RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(
            URL(fileURLWithPath: "/product/backups/vitalserver-helper/20260613T000000Z-manual/nested"),
            runtimeDataBackupsRoot: root
        ))
        XCTAssertFalse(RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(
            URL(fileURLWithPath: "/product/backups/vitalserver-helper/.staging"),
            runtimeDataBackupsRoot: root
        ))
        XCTAssertFalse(RuntimeManagedBackupPolicy.isRuntimeDataBackupURL(
            URL(fileURLWithPath: "/tmp/20260613T000000Z-manual"),
            runtimeDataBackupsRoot: root
        ))
    }
}
