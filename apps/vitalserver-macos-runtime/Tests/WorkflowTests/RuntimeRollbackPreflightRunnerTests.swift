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
            requireLatestBackup: {
                XCTFail("requested backup should not resolve latest backup")
                return URL(fileURLWithPath: "/unused")
            },
            directoryExists: { url in
                events.append("directory:\(url.path)")
                return url == requestedBackup
            },
            fileExists: { url in
                events.append("file:\(url.path)")
                return url == backupRootfs
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
            "directory:/product/backups/backup-1",
            "manifest:/product/backups/backup-1",
            "file:/product/backups/backup-1/rootfs-base.raw.gz",
            "policy",
            "log",
        ])
    }

    func testPrepareFallsBackToLatestBackup() throws {
        let latestBackup = URL(fileURLWithPath: "/product/backups/latest")
        let backupRootfs = latestBackup.appendingPathComponent(rootfsBaseName)
        var events: [String] = []

        let runner = RuntimeRollbackPreflightRunner(
            requireLatestBackup: {
                events.append("latest")
                return latestBackup
            },
            directoryExists: { url in
                events.append("directory:\(url.path)")
                return url == latestBackup
            },
            fileExists: { url in
                events.append("file:\(url.path)")
                return url == backupRootfs
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
            requireLatestBackup: { URL(fileURLWithPath: "/unused") },
            directoryExists: { _ in false },
            fileExists: { _ in
                XCTFail("missing backup directory should stop before file checks")
                return false
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
            requireLatestBackup: { URL(fileURLWithPath: "/unused") },
            directoryExists: { _ in true },
            fileExists: { _ in false },
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
            requireLatestBackup: { URL(fileURLWithPath: "/unused") },
            directoryExists: { _ in true },
            fileExists: { url in
                events.append("file:\(url.path)")
                return false
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
