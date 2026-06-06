import Contracts
import Domain
import Foundation
import Workflow
import XCTest

final class RuntimeRollbackStepExecutorTests: XCTestCase {
    func testExecuteDispatchesRollbackStepsToCollaborators() throws {
        let backup = URL(fileURLWithPath: "/backups/before-1.2.3")
        let policy = RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: true, restartWatchdog: false)
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: backup.appendingPathComponent(rootfsBaseName),
            backupVersion: backup.appendingPathComponent(runtimeVersionName),
            restoresRootfsBase: true,
            restartPolicy: policy
        )
        var events: [String] = []

        let executor = RuntimeRollbackStepExecutor(
            stopRuntimeServices: { events.append("stop") },
            replaceFile: { source, destination in
                events.append("replace:\(source.lastPathComponent):\(destination.lastPathComponent)")
            },
            fileExists: { url in
                events.append("exists:\(url.lastPathComponent)")
                return url.lastPathComponent == runtimeVersionName
            },
            writeRuntimeVersion: { version, bundle in
                events.append("version:\(version):\(bundle.lastPathComponent)")
            },
            restoreBackupPathIfExists: { source, destination in
                events.append("restore:\(source.lastPathComponent):\(destination.lastPathComponent)")
            },
            restoreRuntimeToolsIfExists: { source in
                events.append("tools:\(source.lastPathComponent)")
            },
            startRuntimeServices: { policy in
                events.append("start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
            },
            waitForHealth: { policy in
                events.append("wait:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
            }
        )

        for step in RuntimeOperationPlans.rollback.steps {
            try executor.execute(
                step,
                preflight: preflight,
                rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
                runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version"),
                managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
                nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
                deployDirectory: URL(fileURLWithPath: "/product/deploy")
            )
        }

        XCTAssertEqual(events, [
            "stop",
            "replace:rootfs-base.raw.gz:rootfs-base.raw.gz",
            "exists:runtime-version.json",
            "replace:runtime-version.json:runtime-version",
            "restore:app-bundle:VitalServer Manager.app",
            "restore:nginx-bundle:nginx",
            "restore:guest-deploy:deploy",
            "tools:runtime-tools",
            "start:true:true:false",
            "wait:true:true:false",
        ])
    }

    func testWritesRolledBackVersionWhenBackupVersionIsMissing() throws {
        let backup = URL(fileURLWithPath: "/backups/before-1.2.3")
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: backup.appendingPathComponent(rootfsBaseName),
            backupVersion: backup.appendingPathComponent(runtimeVersionName),
            restoresRootfsBase: true,
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
        )
        var events: [String] = []
        let executor = RuntimeRollbackStepExecutor(
            stopRuntimeServices: {},
            replaceFile: { _, _ in events.append("replace") },
            fileExists: { _ in false },
            writeRuntimeVersion: { version, bundle in events.append("version:\(version):\(bundle.lastPathComponent)") },
            restoreBackupPathIfExists: { _, _ in },
            restoreRuntimeToolsIfExists: { _ in },
            startRuntimeServices: { _ in },
            waitForHealth: { _ in }
        )

        try executor.execute(
            .rollbackRestoreRuntimeVersion,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version"),
            managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
            nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
            deployDirectory: URL(fileURLWithPath: "/product/deploy")
        )

        XCTAssertEqual(events, ["version:rolled-back:before-1.2.3"])
    }

    func testRootfsRestoreRequiresExplicitBackupRootfs() {
        let executor = makeExecutor(replaceFile: { _, _ in XCTFail("should not replace rootfs without backup rootfs") })
        let backup = URL(fileURLWithPath: "/backup")
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: nil,
            backupVersion: backup.appendingPathComponent(runtimeVersionName),
            restoresRootfsBase: false,
            restartPolicy: stoppedPolicy
        )

        XCTAssertThrowsError(try executor.execute(
            .rollbackRestoreRootfsBase,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version"),
            managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
            nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
            deployDirectory: URL(fileURLWithPath: "/product/deploy")
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "rollback rootfs restore requested without backup rootfs"
            )
        }
    }

    func testRejectsNonRollbackStep() {
        let executor = makeExecutor()
        let backup = URL(fileURLWithPath: "/backup")
        let preflight = RollbackPreflightContext(
            backup: backup,
            backupRootfs: backup.appendingPathComponent(rootfsBaseName),
            backupVersion: backup.appendingPathComponent(runtimeVersionName),
            restoresRootfsBase: true,
            restartPolicy: stoppedPolicy
        )

        XCTAssertThrowsError(try executor.execute(
            .stopRuntimeServices,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version"),
            managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
            nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
            deployDirectory: URL(fileURLWithPath: "/product/deploy")
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "unsupported command: rollback step stop-runtime-services"
            )
        }
    }

    private var stoppedPolicy: RuntimeServiceRestartPolicy {
        RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
    }

    private func makeExecutor(
        replaceFile: @escaping (URL, URL) throws -> Void = { _, _ in }
    ) -> RuntimeRollbackStepExecutor {
        RuntimeRollbackStepExecutor(
            stopRuntimeServices: {},
            replaceFile: replaceFile,
            fileExists: { _ in false },
            writeRuntimeVersion: { _, _ in },
            restoreBackupPathIfExists: { _, _ in },
            restoreRuntimeToolsIfExists: { _ in },
            startRuntimeServices: { _ in },
            waitForHealth: { _ in }
        )
    }
}

private let rootfsBaseName = "rootfs-base.raw.gz"
private let runtimeVersionName = "runtime-version.json"
