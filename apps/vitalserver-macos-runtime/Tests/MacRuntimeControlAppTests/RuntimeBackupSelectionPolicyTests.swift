import RuntimeControl
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeBackupSelectionPolicyTests: XCTestCase {
    private let policy = RuntimeBackupSelectionPolicy()

    func testKeepsCurrentSelectionWhenItStillExists() {
        let first = backup("/backups/20260522T000000Z-before-0.1.3")
        let second = backup("/backups/20260523T000000Z-before-0.1.4")

        let selected = policy.selectedBackupPath(from: [first, second], currentSelection: second.path)

        XCTAssertEqual(selected, second.path)
    }

    func testSelectsFirstBackupWhenCurrentSelectionIsMissing() {
        let first = backup("/backups/20260522T000000Z-before-0.1.3")
        let missing = "/backups/missing-before-0.1.2"

        let selected = policy.selectedBackupPath(from: [first], currentSelection: missing)

        XCTAssertEqual(selected, first.path)
    }

    func testClearsSelectionWhenBackupsAreEmpty() {
        let selected = policy.selectedBackupPath(
            from: [],
            currentSelection: "/backups/20260522T000000Z-before-0.1.3"
        )

        XCTAssertEqual(selected, "")
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
        RuntimeBackup(path: path, sizeBytes: nil)
    }
}
