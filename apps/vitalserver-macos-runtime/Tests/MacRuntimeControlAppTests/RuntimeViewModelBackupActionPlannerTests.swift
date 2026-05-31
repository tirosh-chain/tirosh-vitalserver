import Foundation
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeViewModelBackupActionPlannerTests: XCTestCase {
    private let planner = RuntimeViewModelBackupActionPlanner()

    func testRollbackPlanRequiresSelectedBackup() {
        let plan = planner.rollbackPlan(selectedBackupPath: nil)

        XCTAssertEqual(plan.failure, .missingBackup)
    }

    func testRollbackPlanUsesSelectedBackupURL() {
        let backupPath = "/runtime/backups/2026-before-update"
        let plan = planner.rollbackPlan(selectedBackupPath: backupPath)

        XCTAssertEqual(plan.success?.backupURL, URL(fileURLWithPath: backupPath))
    }

    func testDeletePlanRequiresManagedBackupInsideReportedRoot() {
        let invalidOutsideRoot = planner.deletePlan(
            selectedBackupPath: "/other/2026-before-update",
            backupsPath: "/runtime/backups"
        )
        let invalidName = planner.deletePlan(
            selectedBackupPath: "/runtime/backups/manual-copy",
            backupsPath: "/runtime/backups"
        )
        let valid = planner.deletePlan(
            selectedBackupPath: "/runtime/backups/2026-before-update",
            backupsPath: "/runtime/backups"
        )

        XCTAssertEqual(invalidOutsideRoot.failure, .invalidBackup)
        XCTAssertEqual(invalidName.failure, .invalidBackup)
        XCTAssertEqual(valid.success?.backupURL, URL(fileURLWithPath: "/runtime/backups/2026-before-update"))
    }

    func testDeletePlanReportsMissingInputs() {
        XCTAssertEqual(
            planner.deletePlan(selectedBackupPath: nil, backupsPath: "/runtime/backups").failure,
            .missingBackup
        )
        XCTAssertEqual(
            planner.deletePlan(selectedBackupPath: "/runtime/backups/2026-before-update", backupsPath: nil).failure,
            .backupsRootNotReported
        )
    }
}

private extension Result {
    var success: Success? {
        guard case .success(let value) = self else {
            return nil
        }
        return value
    }

    var failure: Failure? {
        guard case .failure(let error) = self else {
            return nil
        }
        return error
    }
}
