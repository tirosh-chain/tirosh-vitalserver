import Management
@testable import MacManagerApp
import XCTest

final class RuntimeBackupSelectionPolicyTests: XCTestCase {
    private let policy = RuntimeBackupSelectionPolicy()

    func testKeepsCurrentSelectionWhenItStillExists() {
        let first = backup("/backups/20260522T000000Z-before-0.1.3")
        let second = backup("/backups/20260523T000000Z-before-0.1.4")

        let selected = policy.selectedBackupURL(from: [first, second], currentSelection: second.url)

        XCTAssertEqual(selected, second.url)
    }

    func testSelectsFirstBackupWhenCurrentSelectionIsMissing() {
        let first = backup("/backups/20260522T000000Z-before-0.1.3")
        let missing = URL(fileURLWithPath: "/backups/missing-before-0.1.2")

        let selected = policy.selectedBackupURL(from: [first], currentSelection: missing)

        XCTAssertEqual(selected, first.url)
    }

    func testClearsSelectionWhenBackupsAreEmpty() {
        let selected = policy.selectedBackupURL(
            from: [],
            currentSelection: URL(fileURLWithPath: "/backups/20260522T000000Z-before-0.1.3")
        )

        XCTAssertNil(selected)
    }

    func testManagedBackupMustBeInsideBackupRootAndUseBackupNameConvention() {
        let root = URL(fileURLWithPath: "/product/backups")

        XCTAssertTrue(policy.isManagedBackupURL(
            URL(fileURLWithPath: "/product/backups/20260522T000000Z-before-0.1.3"),
            backupsRoot: root
        ))
        XCTAssertFalse(policy.isManagedBackupURL(
            URL(fileURLWithPath: "/product/backups/manual-copy"),
            backupsRoot: root
        ))
        XCTAssertFalse(policy.isManagedBackupURL(
            URL(fileURLWithPath: "/tmp/20260522T000000Z-before-0.1.3"),
            backupsRoot: root
        ))
    }

    private func backup(_ path: String) -> RuntimeBackup {
        RuntimeBackup(url: URL(fileURLWithPath: path), sizeBytes: nil)
    }
}
