import Foundation
import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeApplyBundleStepExecutorTests: XCTestCase {
    func testExecuteDispatchesApplyBundleStepsToCollaborators() throws {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let stagedRootfs = stagedBundle.appendingPathComponent(rootfsBaseName)
        let rootfsBase = URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        let artifact = UpdateBundleArtifact(name: "app.tar.gz", type: .appBundle, sha256: "abc", size: 10)
        let migration = UpdateBundleMigration(name: "001-test", sha256: "def", size: 20)
        let manifest = manifest(version: "1.2.3", artifacts: [
            UpdateBundleArtifact(name: rootfsBaseName, type: .rootfsBase, sha256: "root", size: 1),
            artifact,
        ], migrations: [migration])
        let policy = RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: true)
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: stagedBundle,
            manifest: manifest,
            stagedRootfs: stagedRootfs,
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: policy
        )
        var events: [String] = []

        let executor = RuntimeApplyBundleStepExecutor(
            stopRuntimeServices: { events.append("stop") },
            runningVMProcessID: {
                events.append("pid")
                return 123
            },
            stopRuntimeServicesAfterGuestPoweroff: { pid in events.append("stop-after-poweroff:\(pid)") },
            prepareGuestShutdownForUpdate: { manifest in
                events.append("shutdown:\(manifest.version)")
            },
            clearGuestShutdownPreparation: {
                events.append("clear-shutdown")
            },
            createDirectory: { url, withIntermediateDirectories in
                events.append("mkdir:\(url.path):\(withIntermediateDirectories)")
            },
            fileSize: { url in
                events.append("size:\(url.lastPathComponent)")
                return 1_048_576
            },
            replaceFile: { source, destination in
                events.append("replace:\(source.lastPathComponent):\(destination.lastPathComponent)")
            },
            replaceUpdateArtifacts: { artifacts, stagedBundle in
                events.append("artifacts:\(artifacts.count):\(stagedBundle.lastPathComponent)")
            },
            runMigrations: { migrations, stagedBundle in
                events.append("migrations:\(migrations.count):\(stagedBundle.lastPathComponent)")
            },
            refreshCloudInitSeedIfNeeded: { manifest in
                events.append("cloud-init:\(manifest.version)")
            },
            writeRuntimeVersion: { version, bundle in
                events.append("version:\(version):\(bundle.lastPathComponent)")
            },
            startRuntimeServices: { policy in
                events.append("start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
            },
            activateGuestUpdateIfNeeded: { manifest in
                events.append("activate:\(manifest.version)")
            },
            waitForHealth: { policy in
                events.append("wait:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
            },
            log: { _ in }
        )

        for step in RuntimeOperationPlans.applyBundle(updatesRootfsBase: true).steps {
            try executor.execute(step, preflight: preflight, rootfsBase: rootfsBase)
        }

        XCTAssertEqual(events, [
            "pid",
            "shutdown:1.2.3",
            "stop-after-poweroff:123",
            "clear-shutdown",
            "mkdir:/runtime:true",
            "size:rootfs-base.raw.gz",
            "replace:rootfs-base.raw.gz:rootfs-base.raw.gz",
            "artifacts:2:update-bundle-1.2.3",
            "migrations:1:update-bundle-1.2.3",
            "cloud-init:1.2.3",
            "version:1.2.3:update-bundle-1.2.3",
            "start:true:false:true",
            "activate:1.2.3",
            "wait:true:false:true",
        ])
    }

    func testStopRuntimeServicesUsesDirectStopWhenVMWasNotRunning() throws {
        var events: [String] = []
        let executor = makeExecutor(
            stopRuntimeServices: { events.append("stop") },
            runningVMProcessID: {
                events.append("pid")
                return 123
            },
            prepareGuestShutdownForUpdate: { _ in events.append("shutdown") },
            stopRuntimeServicesAfterGuestPoweroff: { _ in events.append("stop-after-poweroff") }
        )

        try executor.execute(
            .stopRuntimeServices,
            preflight: preflight(restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: false,
                restartGuestLogSync: true,
                restartProxy: false,
                restartWatchdog: false
            )),
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )

        XCTAssertEqual(events, ["stop"])
    }

    func testStopRuntimeServicesClearsGuestShutdownPreparationAfterObservedVMStopFailure() {
        var events: [String] = []
        let executor = makeExecutor(
            runningVMProcessID: {
                events.append("pid")
                return 123
            },
            prepareGuestShutdownForUpdate: { _ in events.append("shutdown") },
            stopRuntimeServicesAfterGuestPoweroff: { pid in
                events.append("stop-after-poweroff:\(pid)")
                throw TestError.vmStopFailed
            },
            clearGuestShutdownPreparation: { events.append("clear-shutdown") }
        )

        XCTAssertThrowsError(try executor.execute(
            .stopRuntimeServices,
            preflight: preflight(restartPolicy: RuntimeServiceRestartPolicy(
                restartVM: true,
                restartGuestLogSync: true,
                restartProxy: false,
                restartWatchdog: false
            )),
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )) { error in
            XCTAssertEqual(error as? TestError, .vmStopFailed)
        }
        XCTAssertEqual(events, [
            "pid",
            "shutdown",
            "stop-after-poweroff:123",
            "clear-shutdown",
        ])
    }

    func testRootfsReplacementStepSkipsWhenBundleDoesNotIncludeRootfs() throws {
        let executor = RuntimeApplyBundleStepExecutor(
            stopRuntimeServices: {},
            runningVMProcessID: { 123 },
            stopRuntimeServicesAfterGuestPoweroff: { _ in },
            prepareGuestShutdownForUpdate: { _ in },
            clearGuestShutdownPreparation: {},
            createDirectory: { _, _ in XCTFail("should not create rootfs directory") },
            fileSize: { _ in XCTFail("should not read rootfs size"); return 0 },
            replaceFile: { _, _ in XCTFail("should not replace rootfs") },
            replaceUpdateArtifacts: { _, _ in },
            runMigrations: { _, _ in },
            refreshCloudInitSeedIfNeeded: { _ in },
            writeRuntimeVersion: { _, _ in },
            startRuntimeServices: { _ in },
            activateGuestUpdateIfNeeded: { _ in },
            waitForHealth: { _ in },
            log: { _ in }
        )
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/staged"),
            manifest: manifest(version: "1.2.3"),
            stagedRootfs: nil,
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
        )

        try executor.execute(
            .replaceRootfsBase,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )
    }

    func testRootfsReplacementPropagatesPermissionFailure() {
        let permissionError = CocoaError(.fileWriteNoPermission)
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/staged"),
            manifest: manifest(version: "1.2.3", artifacts: [
                UpdateBundleArtifact(name: rootfsBaseName, type: .rootfsBase, sha256: "abc", size: 10),
            ]),
            stagedRootfs: URL(fileURLWithPath: "/staged/rootfs-base.raw.gz"),
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
        )
        let executor = makeExecutor(replaceFile: { _, _ in throw permissionError })

        XCTAssertThrowsError(try executor.execute(
            .replaceRootfsBase,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )) { error in
            XCTAssertFileWriteNoPermission(error)
        }
    }

    func testUpdateArtifactReplacementPropagatesPermissionFailure() {
        let permissionError = CocoaError(.fileWriteNoPermission)
        let artifact = UpdateBundleArtifact(name: "app.tar.gz", type: .appBundle, sha256: "abc", size: 10)
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/staged"),
            manifest: manifest(version: "1.2.3", artifacts: [artifact]),
            stagedRootfs: nil,
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
        )
        let executor = makeExecutor(replaceUpdateArtifacts: { artifacts, stagedBundle in
            XCTAssertEqual(artifacts, [artifact])
            XCTAssertEqual(stagedBundle.path, "/staged")
            throw permissionError
        })

        XCTAssertThrowsError(try executor.execute(
            .replaceUpdateArtifacts,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )) { error in
            XCTAssertFileWriteNoPermission(error)
        }
    }

    func testStopRuntimeServicesLogsGuestShutdownPreparationCleanupFailure() throws {
        var logs: [String] = []
        let executor = RuntimeApplyBundleStepExecutor(
            stopRuntimeServices: {},
            runningVMProcessID: { 123 },
            stopRuntimeServicesAfterGuestPoweroff: { _ in },
            prepareGuestShutdownForUpdate: { _ in },
            clearGuestShutdownPreparation: {
                throw TestError.clearFailed
            },
            createDirectory: { _, _ in },
            fileSize: { _ in 0 },
            replaceFile: { _, _ in },
            replaceUpdateArtifacts: { _, _ in },
            runMigrations: { _, _ in },
            refreshCloudInitSeedIfNeeded: { _ in },
            writeRuntimeVersion: { _, _ in },
            startRuntimeServices: { _ in },
            activateGuestUpdateIfNeeded: { _ in },
            waitForHealth: { _ in },
            log: { logs.append($0) }
        )
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/staged"),
            manifest: manifest(version: "1.2.3"),
            stagedRootfs: URL(fileURLWithPath: "/staged/rootfs-base.raw.gz"),
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: false)
        )

        try executor.execute(
            .stopRuntimeServices,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        )

        XCTAssertTrue(logs.contains { $0.contains("guest shutdown preparation cleanup failed") })
    }

    func testRejectsNonApplyBundleStep() {
        let executor = RuntimeApplyBundleStepExecutor(
            stopRuntimeServices: {},
            runningVMProcessID: { 123 },
            stopRuntimeServicesAfterGuestPoweroff: { _ in },
            prepareGuestShutdownForUpdate: { _ in },
            clearGuestShutdownPreparation: {},
            createDirectory: { _, _ in },
            fileSize: { _ in 0 },
            replaceFile: { _, _ in },
            replaceUpdateArtifacts: { _, _ in },
            runMigrations: { _, _ in },
            refreshCloudInitSeedIfNeeded: { _ in },
            writeRuntimeVersion: { _, _ in },
            startRuntimeServices: { _ in },
            activateGuestUpdateIfNeeded: { _ in },
            waitForHealth: { _ in },
            log: { _ in }
        )
        let preflight = ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/staged"),
            manifest: manifest(version: "1.2.3"),
            stagedRootfs: URL(fileURLWithPath: "/staged/rootfs-base.raw.gz"),
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
        )

        XCTAssertThrowsError(try executor.execute(
            .loadInstallSettings,
            preflight: preflight,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz")
        ))
    }

    private var rootfsBaseName: String {
        "rootfs-base.raw.gz"
    }

    private func preflight(
        restartPolicy: RuntimeServiceRestartPolicy
    ) -> ApplyBundlePreflightContext {
        ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/staged"),
            manifest: manifest(version: "1.2.3"),
            stagedRootfs: URL(fileURLWithPath: "/staged/rootfs-base.raw.gz"),
            backup: URL(fileURLWithPath: "/backup"),
            restartPolicy: restartPolicy
        )
    }

    private func manifest(
        version: String,
        artifacts: [UpdateBundleArtifact] = [],
        migrations: [UpdateBundleMigration] = []
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "test-product",
            helperVersion: version,
            releaseLabel: version,
            targetPlatform: "macos-arm64",
            components: ["updater": version],
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts,
            migrations: migrations
        )
    }

    private func makeExecutor(
        stopRuntimeServices: @escaping () throws -> Void = {},
        runningVMProcessID: @escaping () throws -> pid_t = { 123 },
        prepareGuestShutdownForUpdate: @escaping (UpdateBundleManifest) throws -> Void = { _ in },
        stopRuntimeServicesAfterGuestPoweroff: @escaping (pid_t) throws -> Void = { _ in },
        clearGuestShutdownPreparation: @escaping () throws -> Void = {},
        replaceFile: @escaping (URL, URL) throws -> Void = { _, _ in },
        replaceUpdateArtifacts: @escaping ([UpdateBundleArtifact], URL) throws -> Void = { _, _ in }
    ) -> RuntimeApplyBundleStepExecutor {
        RuntimeApplyBundleStepExecutor(
            stopRuntimeServices: stopRuntimeServices,
            runningVMProcessID: runningVMProcessID,
            stopRuntimeServicesAfterGuestPoweroff: stopRuntimeServicesAfterGuestPoweroff,
            prepareGuestShutdownForUpdate: prepareGuestShutdownForUpdate,
            clearGuestShutdownPreparation: clearGuestShutdownPreparation,
            createDirectory: { _, _ in },
            fileSize: { _ in 10 },
            replaceFile: replaceFile,
            replaceUpdateArtifacts: replaceUpdateArtifacts,
            runMigrations: { _, _ in },
            refreshCloudInitSeedIfNeeded: { _ in },
            writeRuntimeVersion: { _, _ in },
            startRuntimeServices: { _ in },
            activateGuestUpdateIfNeeded: { _ in },
            waitForHealth: { _ in },
            log: { _ in }
        )
    }

    private func XCTAssertFileWriteNoPermission(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nsError = error as NSError
        XCTAssertEqual(nsError.domain, NSCocoaErrorDomain, file: file, line: line)
        XCTAssertEqual(nsError.code, CocoaError.Code.fileWriteNoPermission.rawValue, file: file, line: line)
    }
}

private enum TestError: Error, Equatable {
    case vmStopFailed
    case clearFailed
}
