import Foundation
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeBackupActionPlannerTests: XCTestCase {
    private let planner = RuntimeBackupActionPlanner()

    func testRollbackPlanRequiresSelectedBackup() {
        let plan = planner.rollbackPlan(selectedBackupPath: nil)

        XCTAssertEqual(plan.failure, .missingBackup)
    }

    func testRollbackPlanUsesSelectedBackupURL() {
        let backupPath = "/runtime/backups/2026-before-update"
        let plan = planner.rollbackPlan(selectedBackupPath: backupPath)

        XCTAssertEqual(plan.success?.backupURL, URL(fileURLWithPath: backupPath))
    }

    func testDeleteUpdateBackupPlanRequiresManagedBackupInsideReportedRoot() {
        let invalidOutsideRoot = planner.deleteUpdateBackupPlan(
            selectedBackupPath: "/other/2026-before-update",
            backupsPath: "/runtime/backups"
        )
        let invalidName = planner.deleteUpdateBackupPlan(
            selectedBackupPath: "/runtime/backups/manual-copy",
            backupsPath: "/runtime/backups"
        )
        let valid = planner.deleteUpdateBackupPlan(
            selectedBackupPath: "/runtime/backups/2026-before-update",
            backupsPath: "/runtime/backups"
        )

        XCTAssertEqual(invalidOutsideRoot.failure, .invalidBackup)
        XCTAssertEqual(invalidName.failure, .invalidBackup)
        XCTAssertEqual(valid.success?.backupURL, URL(fileURLWithPath: "/runtime/backups/2026-before-update"))
    }

    func testDeletePlanReportsMissingInputs() {
        XCTAssertEqual(
            planner.deleteUpdateBackupPlan(selectedBackupPath: nil, backupsPath: "/runtime/backups").failure,
            .missingBackup
        )
        XCTAssertEqual(
            planner.deleteUpdateBackupPlan(
                selectedBackupPath: "/runtime/backups/2026-before-update",
                backupsPath: nil
            ).failure,
            .backupsRootNotReported
        )
    }

    func testDeleteRuntimeDataBackupPlanRequiresDirectBackupInsideReportedRoot() {
        let invalidOutsideRoot = planner.deleteRuntimeDataBackupPlan(
            selectedBackupPath: "/other/20260613T000000Z-manual",
            runtimeDataBackupsPath: "/runtime/backups/runtime-data"
        )
        let invalidNestedPath = planner.deleteRuntimeDataBackupPlan(
            selectedBackupPath: "/runtime/backups/runtime-data/20260613T000000Z-manual/nested",
            runtimeDataBackupsPath: "/runtime/backups/runtime-data"
        )
        let invalidHiddenName = planner.deleteRuntimeDataBackupPlan(
            selectedBackupPath: "/runtime/backups/runtime-data/.staging",
            runtimeDataBackupsPath: "/runtime/backups/runtime-data"
        )
        let valid = planner.deleteRuntimeDataBackupPlan(
            selectedBackupPath: "/runtime/backups/runtime-data/20260613T000000Z-manual",
            runtimeDataBackupsPath: "/runtime/backups/runtime-data"
        )

        XCTAssertEqual(invalidOutsideRoot.failure, .invalidBackup)
        XCTAssertEqual(invalidNestedPath.failure, .invalidBackup)
        XCTAssertEqual(invalidHiddenName.failure, .invalidBackup)
        XCTAssertEqual(valid.success?.backupURL, URL(fileURLWithPath: "/runtime/backups/runtime-data/20260613T000000Z-manual"))
    }

    func testDeleteRuntimeDataBackupPlanReportsMissingInputs() {
        XCTAssertEqual(
            planner.deleteRuntimeDataBackupPlan(
                selectedBackupPath: nil,
                runtimeDataBackupsPath: "/runtime/backups/runtime-data"
            ).failure,
            .missingBackup
        )
        XCTAssertEqual(
            planner.deleteRuntimeDataBackupPlan(
                selectedBackupPath: "/runtime/backups/runtime-data/20260613T000000Z-manual",
                runtimeDataBackupsPath: nil
            ).failure,
            .backupsRootNotReported
        )
    }

    func testRestoreRedisBackupPlanRequiresRedisArchiveInsideReportedRoot() {
        let invalidOutsideRoot = planner.restoreRedisBackupPlan(
            selectedBackupPath: "/other/redis-20260614T000000Z.tar.gz",
            redisBackupsPath: "/runtime/backups/redis"
        )
        let invalidName = planner.restoreRedisBackupPlan(
            selectedBackupPath: "/runtime/backups/redis/manual.tar.gz",
            redisBackupsPath: "/runtime/backups/redis"
        )
        let valid = planner.restoreRedisBackupPlan(
            selectedBackupPath: "/runtime/backups/redis/redis-20260614T000000Z.tar.gz",
            redisBackupsPath: "/runtime/backups/redis"
        )

        XCTAssertEqual(invalidOutsideRoot.failure, .invalidBackup)
        XCTAssertEqual(invalidName.failure, .invalidBackup)
        XCTAssertEqual(valid.success?.backupURL, URL(fileURLWithPath: "/runtime/backups/redis/redis-20260614T000000Z.tar.gz"))
    }

    func testImportRuntimeDataBackupPlanCopiesFolderIntoRuntimeDataBackupRoot() {
        let plan = planner.importRuntimeDataBackupPlan(
            sourceBackupURL: URL(fileURLWithPath: "/external/20260614T043455Z-manual", isDirectory: true),
            runtimeDataBackupsRoot: URL(fileURLWithPath: "/runtime/backups/runtime-data", isDirectory: true),
            sourcePathState: .directory,
            destinationPathState: .missing
        )

        XCTAssertEqual(plan.success?.sourceURL.path, "/external/20260614T043455Z-manual")
        XCTAssertEqual(plan.success?.destinationURL.path, "/runtime/backups/runtime-data/20260614T043455Z-manual")
    }

    func testImportRuntimeDataBackupPlanRejectsNonDirectorySourceAndExistingDestination() {
        let source = URL(fileURLWithPath: "/external/20260614T043455Z-manual")
        let root = URL(fileURLWithPath: "/runtime/backups/runtime-data", isDirectory: true)

        XCTAssertEqual(
            planner.importRuntimeDataBackupPlan(
                sourceBackupURL: source,
                runtimeDataBackupsRoot: root,
                sourcePathState: .file,
                destinationPathState: .missing
            ).failure,
            .sourceIsNotDirectory
        )
        XCTAssertEqual(
            planner.importRuntimeDataBackupPlan(
                sourceBackupURL: source,
                runtimeDataBackupsRoot: root,
                sourcePathState: .missing,
                destinationPathState: .missing
            ).failure,
            .sourcePathUnavailable("missing")
        )
        XCTAssertEqual(
            planner.importRuntimeDataBackupPlan(
                sourceBackupURL: source,
                runtimeDataBackupsRoot: root,
                sourcePathState: .directory,
                destinationPathState: .directory
            ).failure,
            .destinationAlreadyExists
        )
        XCTAssertEqual(
            planner.importRuntimeDataBackupPlan(
                sourceBackupURL: source,
                runtimeDataBackupsRoot: root,
                sourcePathState: .directory,
                destinationPathState: .unknown("stale")
            ).failure,
            .destinationPathUnavailable("stale")
        )
    }

    func testImportRedisBackupPlanCopiesArchiveIntoRedisBackupRoot() {
        let plan = planner.importRedisBackupPlan(
            sourceBackupURL: URL(fileURLWithPath: "/external/redis-20260614T043455Z.tar.gz"),
            redisBackupsRoot: URL(fileURLWithPath: "/runtime/backups/redis", isDirectory: true),
            sourcePathState: .file,
            destinationPathState: .missing
        )

        XCTAssertEqual(plan.success?.sourceURL.path, "/external/redis-20260614T043455Z.tar.gz")
        XCTAssertEqual(plan.success?.destinationURL.path, "/runtime/backups/redis/redis-20260614T043455Z.tar.gz")
    }

    func testImportRedisBackupPlanRejectsInvalidArchiveInputs() {
        let source = URL(fileURLWithPath: "/external/manual.tar.gz")
        let root = URL(fileURLWithPath: "/runtime/backups/redis", isDirectory: true)

        XCTAssertEqual(
            planner.importRedisBackupPlan(
                sourceBackupURL: source,
                redisBackupsRoot: root,
                sourcePathState: .file,
                destinationPathState: .missing
            ).failure,
            .invalidBackup
        )
        XCTAssertEqual(
            planner.importRedisBackupPlan(
                sourceBackupURL: URL(fileURLWithPath: "/external/redis-20260614T043455Z.tar.gz"),
                redisBackupsRoot: root,
                sourcePathState: .directory,
                destinationPathState: .missing
            ).failure,
            .sourceIsNotFile
        )
        XCTAssertEqual(
            planner.importRedisBackupPlan(
                sourceBackupURL: URL(fileURLWithPath: "/external/redis-20260614T043455Z.tar.gz"),
                redisBackupsRoot: root,
                sourcePathState: .file,
                destinationPathState: .file
            ).failure,
            .destinationAlreadyExists
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
