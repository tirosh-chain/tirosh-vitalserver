import Application
import Contracts
import Domain
import Foundation
import Workflow
import XCTest
import Errors

final class RuntimeRollbackPreflightRunnerTests: XCTestCase {
    func testPrepareUsesRequestedBackupAndBuildsContext() throws {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/backup-1")
        let backupRootfs = requestedBackup.appendingPathComponent(rootfsBaseName)
        var events: [String] = []

        let runner = RuntimeRollbackPreflightRunner(
            resolveBackupSelection: { selection in
                events.append("selection:\(selectionLabel(selection))")
                switch selection {
                case .specificBackup(let backup):
                    return backup
                case .latestBackup:
                    XCTFail("requested backup should not resolve latest backup")
                    return URL(fileURLWithPath: "/unused")
                }
            },
            resolveBackupDirectory: { url in
                events.append("directory:\(url.path)")
                return try executeBackupDirectoryDecision(url == requestedBackup
                    ? .loadManifest(url)
                    : .failed(message: "missing file: \(url.path)")
                )
            },
            resolveBackupRootfs: { plan in
                events.append("file:\(plan.backupRootfs?.path ?? "none")")
                return try executeBackupRootfsDecision(plan.backupRootfs == backupRootfs
                    ? .proceed(plan)
                    : .failed(message: "missing file: \(plan.backupRootfs?.path ?? "unknown")")
                )
            },
            loadManifest: { url in
                events.append("manifest:\(url.path)")
                return self.backupManifest(rootfsBase: rootfsBaseName)
            },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: true)
            },
            log: { _ in events.append("log") }
        )

        let context = try runner.prepare(.specificBackup(requestedBackup))

        XCTAssertEqual(context.backup, requestedBackup)
        XCTAssertEqual(context.backupRootfs, backupRootfs)
        XCTAssertEqual(context.backupVersion, requestedBackup.appendingPathComponent(runtimeVersionName))
        XCTAssertTrue(context.restoresRootfsBase)
        XCTAssertEqual(context.restartPolicy, RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: true
        ))
        XCTAssertEqual(events, [
            "selection:specific:/product/backups/backup-1",
            "directory:/product/backups/backup-1",
            "manifest:/product/backups/backup-1",
            "file:/product/backups/backup-1/rootfs-base.raw.gz",
            "policy",
            "log",
        ])
    }

    func testPrepareResolvesLatestBackupSelectionThroughPort() throws {
        let latestBackup = URL(fileURLWithPath: "/product/backups/latest")
        let backupRootfs = latestBackup.appendingPathComponent(rootfsBaseName)
        var events: [String] = []

        let runner = RuntimeRollbackPreflightRunner(
            resolveBackupSelection: { selection in
                events.append("selection:\(selectionLabel(selection))")
                switch selection {
                case .latestBackup:
                    events.append("latest")
                    return latestBackup
                case .specificBackup:
                    XCTFail("latest command should not request a specific backup")
                    return URL(fileURLWithPath: "/unused")
                }
            },
            resolveBackupDirectory: { url in
                events.append("directory:\(url.path)")
                return try executeBackupDirectoryDecision(url == latestBackup
                    ? .loadManifest(url)
                    : .failed(message: "missing file: \(url.path)")
                )
            },
            resolveBackupRootfs: { plan in
                events.append("file:\(plan.backupRootfs?.path ?? "none")")
                return try executeBackupRootfsDecision(plan.backupRootfs == backupRootfs
                    ? .proceed(plan)
                    : .failed(message: "missing file: \(plan.backupRootfs?.path ?? "unknown")")
                )
            },
            loadManifest: { url in
                events.append("manifest:\(url.path)")
                return self.backupManifest(rootfsBase: rootfsBaseName)
            },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: true, restartWatchdog: false)
            },
            log: { _ in events.append("log") }
        )

        let context = try runner.prepare(.latestBackup)

        XCTAssertEqual(context.backup, latestBackup)
        XCTAssertEqual(context.restartPolicy, RuntimeServiceRestartPolicy(
            restartVM: false,
            restartGuestLogSync: false,
            restartProxy: true,
            restartWatchdog: false
        ))
        XCTAssertEqual(events, [
            "selection:latest",
            "latest",
            "directory:/product/backups/latest",
            "manifest:/product/backups/latest",
            "file:/product/backups/latest/rootfs-base.raw.gz",
            "policy",
            "log",
        ])
    }

    func testPrepareFailsWhenBackupDirectoryIsMissing() {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/missing")
        let runner = RuntimeRollbackPreflightRunner(
            resolveBackupSelection: { _ in requestedBackup },
            resolveBackupDirectory: { backup in
                throw RuntimeRollbackWorkflowError.operationFailed("missing file: \(backup.path)")
            },
            resolveBackupRootfs: { plan in
                XCTFail("missing backup directory should stop before rootfs observation")
                return plan
            },
            loadManifest: { _ in
                XCTFail("missing backup directory should stop before manifest load")
                return self.backupManifest(rootfsBase: rootfsBaseName)
            },
            serviceRestartPolicy: {
                XCTFail("missing backup directory should stop before service policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
            },
            log: { _ in XCTFail("missing backup directory should stop before logging") }
        )

        XCTAssertThrowsError(try runner.prepare(.specificBackup(requestedBackup))) { error in
            XCTAssertEqual(String(describing: error), "missing file: \(requestedBackup.path)")
        }
    }

    func testPrepareFailsWhenBackupRootfsIsMissing() {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/backup-1")
        let missingRootfs = requestedBackup.appendingPathComponent(rootfsBaseName)
        let runner = RuntimeRollbackPreflightRunner(
            resolveBackupSelection: { _ in requestedBackup },
            resolveBackupDirectory: { backup in
                backup
            },
            resolveBackupRootfs: { _ in
                throw RuntimeRollbackWorkflowError.operationFailed("missing file: \(missingRootfs.path)")
            },
            loadManifest: { _ in self.backupManifest(rootfsBase: rootfsBaseName) },
            serviceRestartPolicy: {
                XCTFail("missing rootfs should stop before service policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
            },
            log: { _ in XCTFail("missing rootfs should stop before logging") }
        )

        XCTAssertThrowsError(try runner.prepare(.specificBackup(requestedBackup))) { error in
            XCTAssertEqual(String(describing: error), "missing file: \(missingRootfs.path)")
        }
    }

    func testPrepareSkipsRootfsRestoreWhenManifestDoesNotDeclareRootfs() throws {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/backup-1")
        var events: [String] = []
        let runner = RuntimeRollbackPreflightRunner(
            resolveBackupSelection: { _ in requestedBackup },
            resolveBackupDirectory: { backup in
                backup
            },
            resolveBackupRootfs: { plan in
                if let backupRootfs = plan.backupRootfs {
                    events.append("file:\(backupRootfs.path)")
                }
                return plan
            },
            loadManifest: { _ in self.backupManifest(rootfsBase: nil) },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
            },
            log: { _ in events.append("log") }
        )

        let context = try runner.prepare(.specificBackup(requestedBackup))

        XCTAssertNil(context.backupRootfs)
        XCTAssertFalse(context.restoresRootfsBase)
        XCTAssertEqual(events, ["policy", "log"])
    }

    private func backupManifest(rootfsBase: String?) -> BackupManifest {
        BackupManifest(
            product: "ai.tirosh.vitalserver.helper",
            createdAt: "2026-05-31T00:00:00Z",
            reason: "before-1.2.3",
            rootfsBase: rootfsBase,
            vmDisk: "vm-disk.img",
            vmDiskPreserved: true
        )
    }
}

private let rootfsBaseName = "rootfs-base.raw.gz"
private let runtimeVersionName = "runtime-version.json"

private func executeBackupDirectoryDecision(
    _ decision: RollbackRuntimeBackupDirectoryDecision
) throws -> URL {
    switch decision {
    case .loadManifest(let backup):
        return backup
    case .failed(let message):
        throw RuntimeRollbackWorkflowError.operationFailed(message)
    }
}

private func executeBackupRootfsDecision(
    _ decision: RollbackRuntimeBackupRootfsDecision
) throws -> RollbackRuntimeBackupPlan {
    switch decision {
    case .proceed(let plan):
        return plan
    case .failed(let message):
        throw RuntimeRollbackWorkflowError.operationFailed(message)
    }
}

private func selectionLabel(_ selection: RollbackRuntimeBackupSelection) -> String {
    switch selection {
    case .latestBackup:
        return "latest"
    case .specificBackup(let backup):
        return "specific:\(backup.path)"
    }
}
