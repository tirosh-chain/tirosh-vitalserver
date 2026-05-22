import Foundation
import RuntimeCore
@testable import HostRuntimeControl
import XCTest

final class RuntimeRollbackPreflightRunnerTests: XCTestCase {
    func testPrepareUsesRequestedBackupAndBuildsContext() throws {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/backup-1")
        let backupRootfs = requestedBackup.appendingPathComponent(Constants.Artifacts.rootfsBase)
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
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartProxy: false, restartWatchdog: true)
            },
            log: { _ in events.append("log") }
        )

        let context = try runner.prepare(requestedBackup: requestedBackup)

        XCTAssertEqual(context.backup, requestedBackup)
        XCTAssertEqual(context.backupRootfs, backupRootfs)
        XCTAssertEqual(context.backupVersion, requestedBackup.appendingPathComponent(Constants.Artifacts.runtimeVersion))
        XCTAssertEqual(context.restartPolicy, RuntimeServiceRestartPolicy(
            restartVM: true,
            restartProxy: false,
            restartWatchdog: true
        ))
        XCTAssertEqual(events, [
            "directory:/product/backups/backup-1",
            "file:/product/backups/backup-1/rootfs-base.raw.gz",
            "policy",
            "log",
        ])
    }

    func testPrepareFallsBackToLatestBackup() throws {
        let latestBackup = URL(fileURLWithPath: "/product/backups/latest")
        let backupRootfs = latestBackup.appendingPathComponent(Constants.Artifacts.rootfsBase)
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
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartProxy: true, restartWatchdog: false)
            },
            log: { _ in events.append("log") }
        )

        let context = try runner.prepare(requestedBackup: nil)

        XCTAssertEqual(context.backup, latestBackup)
        XCTAssertEqual(context.restartPolicy, RuntimeServiceRestartPolicy(
            restartVM: false,
            restartProxy: true,
            restartWatchdog: false
        ))
        XCTAssertEqual(events, [
            "latest",
            "directory:/product/backups/latest",
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
            serviceRestartPolicy: {
                XCTFail("missing backup directory should stop before service policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartProxy: false, restartWatchdog: false)
            },
            log: { _ in XCTFail("missing backup directory should stop before logging") }
        )

        XCTAssertThrowsError(try runner.prepare(requestedBackup: requestedBackup)) { error in
            XCTAssertEqual(String(describing: error), String(describing: LauncherError.missingFile(requestedBackup.path)))
        }
    }

    func testPrepareFailsWhenBackupRootfsIsMissing() {
        let requestedBackup = URL(fileURLWithPath: "/product/backups/backup-1")
        let missingRootfs = requestedBackup.appendingPathComponent(Constants.Artifacts.rootfsBase)
        let runner = RuntimeRollbackPreflightRunner(
            requireLatestBackup: { URL(fileURLWithPath: "/unused") },
            directoryExists: { _ in true },
            fileExists: { _ in false },
            serviceRestartPolicy: {
                XCTFail("missing rootfs should stop before service policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartProxy: false, restartWatchdog: false)
            },
            log: { _ in XCTFail("missing rootfs should stop before logging") }
        )

        XCTAssertThrowsError(try runner.prepare(requestedBackup: requestedBackup)) { error in
            XCTAssertEqual(String(describing: error), String(describing: LauncherError.missingFile(missingRootfs.path)))
        }
    }
}
