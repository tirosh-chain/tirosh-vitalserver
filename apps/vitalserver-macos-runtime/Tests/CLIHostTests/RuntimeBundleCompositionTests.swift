import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeBundleCompositionTests: XCTestCase {
    func testRemoveMaterializedBundleTemporaryRootRecordsCleanupFailure() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.removeItemError = CocoaError(.fileWriteNoPermission)
        let temporaryRoot = URL(fileURLWithPath: "/tmp/tirosh-update-bundle-test")
        var logs: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            log: { logs.append($0) }
        )

        workflow.removeMaterializedBundleTemporaryRoot(temporaryRoot)

        XCTAssertTrue(logs.contains { $0.contains("bundle temporary directory cleanup failed") })
        XCTAssertTrue(logs.contains { $0.contains(temporaryRoot.path) })
    }

    func testStageBundlePropagatesExistingDestinationPermissionFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/input/update-bundle")
        let destination = URL(fileURLWithPath: "/product/bundles/update-bundle-1.2.3")
        try writeEmptyBundle(at: source, to: fileStore)
        fileStore.directories.insert(destination)
        fileStore.removeItemError = CocoaError(.fileWriteNoPermission)
        var logs: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try workflow.stageBundle(source)) { error in
            XCTAssertFileWriteNoPermission(error)
        }
        XCTAssertTrue(logs.contains { $0.contains("removing existing staged bundle") })
        XCTAssertTrue(fileStore.removed.isEmpty)
    }

    func testStageBundlePropagatesManagedStorageCopyPermissionFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/input/update-bundle")
        try writeEmptyBundle(at: source, to: fileStore)
        fileStore.copyItemError = CocoaError(.fileWriteNoPermission)
        var logs: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try workflow.stageBundle(source)) { error in
            XCTAssertFileWriteNoPermission(error)
        }
        XCTAssertTrue(logs.contains { $0.contains("copying bundle to managed storage") })
    }

    func testApplyBundleGuestShutdownCleanupFailureIsLoggedWithoutHidingStopFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/input/update-bundle")
        try writeEmptyBundle(at: source, to: fileStore)
        var events: [String] = []
        var logs: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            startRuntimeServices: { _ in events.append("start") },
            runningVMProcessID: {
                events.append("pid")
                return 123
            },
            stopRuntimeServicesAfterGuestPoweroff: { pid in
                events.append("stop-after-poweroff:\(pid)")
                throw TestRuntimeBundleCompositionError.vmStopFailed
            },
            prepareGuestShutdownForUpdate: { _ in events.append("shutdown") },
            clearGuestShutdownPreparation: {
                events.append("clear-shutdown")
                throw TestRuntimeBundleCompositionError.cleanupFailed
            },
            isLaunchdLoaded: { service in service == .vm },
            rollback: { _ in events.append("rollback") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try workflow.applyBundle(source)) { error in
            XCTAssertEqual(error as? TestRuntimeBundleCompositionError, .vmStopFailed)
        }

        XCTAssertEqual(events, [
            "pid",
            "shutdown",
            "stop-after-poweroff:123",
            "clear-shutdown",
            "rollback",
            "start",
        ])
        XCTAssertTrue(logs.contains { $0.contains("guest shutdown preparation cleanup failed") })
        XCTAssertTrue(logs.contains { $0.contains("cleanupFailed") })
    }

    func testApplyBundleRecoveryLogsRollbackAndRestartFailuresWithoutHidingApplyFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/input/update-bundle")
        try writeEmptyBundle(at: source, to: fileStore)
        var events: [String] = []
        var logs: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            startRuntimeServices: { _ in
                events.append("start")
                throw TestRuntimeBundleCompositionError.restartFailed
            },
            stopRuntimeServices: {
                events.append("stop")
                throw TestRuntimeBundleCompositionError.vmStopFailed
            },
            rollback: { _ in
                events.append("rollback")
                throw TestRuntimeBundleCompositionError.rollbackFailed
            },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try workflow.applyBundle(source)) { error in
            XCTAssertEqual(error as? TestRuntimeBundleCompositionError, .vmStopFailed)
        }

        XCTAssertEqual(events, ["stop", "rollback", "start"])
        XCTAssertTrue(logs.contains { $0.contains("bundle apply rollback failed error=rollbackFailed") })
        XCTAssertTrue(logs.contains { $0.contains("failed to restart runtime services after rollback failure error=restartFailed") })
    }

    private func makeWorkflow(
        fileStore: RuntimeFileStore,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void = { _ in },
        stopRuntimeServices: @escaping () throws -> Void = {},
        runningVMProcessID: @escaping () throws -> pid_t = { 123 },
        stopRuntimeServicesAfterGuestPoweroff: @escaping (pid_t) throws -> Void = { _ in },
        prepareGuestShutdownForUpdate: @escaping (UpdateBundleManifest) throws -> Void = { _ in },
        clearGuestShutdownPreparation: @escaping () throws -> Void = {},
        isLaunchdLoaded: @escaping (RuntimeManagedService) -> Bool = { _ in false },
        rollback: @escaping (URL?) throws -> Void = { _ in },
        rotateRuntimeLogs: @escaping () throws -> Void = {},
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeBundleComposition {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        return RuntimeBundleComposition(
            context: RuntimeBundleCompositionContext(
                installedPaths: installedPaths,
                bundlesDirectory: URL(fileURLWithPath: "/product/bundles"),
                backupsDirectory: URL(fileURLWithPath: "/product/backups"),
                logsDirectory: URL(fileURLWithPath: "/product/logs"),
                rootfsBase: URL(fileURLWithPath: "/product/rootfs-base.raw.gz"),
                vmDisk: URL(fileURLWithPath: "/product/vm-disk.img")
            ),
            operations: RuntimeBundleCompositionOperations(
                fileStore: fileStore,
                runtimeHealthSnapshot: { Self.healthSnapshot() },
                rotateRuntimeLogs: rotateRuntimeLogs,
                rollback: rollback,
                startRuntimeServices: startRuntimeServices,
                stopRuntimeServices: stopRuntimeServices,
                runningVMProcessID: runningVMProcessID,
                stopRuntimeServicesAfterGuestPoweroff: stopRuntimeServicesAfterGuestPoweroff,
                prepareGuestShutdownForUpdate: prepareGuestShutdownForUpdate,
                clearGuestShutdownPreparation: clearGuestShutdownPreparation,
                isLaunchdLoaded: isLaunchdLoaded,
                createBackup: { _ in URL(fileURLWithPath: "/product/backups/backup") },
                statusReporter: RuntimeWorkflowStatusReporter(
                    writeStatus: { _, _, _ in },
                    writeProgress: { _ in },
                    log: log
                ),
                pruneOldRuntimeArtifacts: {},
                requireFreeSpace: { _, _, _ in },
                runProcess: { _, _ in RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "") },
                runRequired: { _, _ in },
                runProcessToFile: { _, _, _ in },
                replaceFile: { _, _ in },
                writeRuntimeVersion: { _, _ in },
                refreshCloudInitSeedIfNeeded: { _ in },
                activateGuestUpdateIfNeeded: { _ in },
                waitForHealth: { _ in },
                requireGuestCapability: { _ in },
                log: log
            )
        )
    }

    private static func healthSnapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmIP: "192.168.64.2",
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: []
        )
    }

    private func writeEmptyBundle(at source: URL, to fileStore: RuntimeFileStoreSpy) throws {
        let manifest = UpdateBundleManifest(
            schemaVersion: 3,
            product: Constants.Product.identifier,
            helperVersion: "1.2.3",
            releaseLabel: "1.2.3",
            targetPlatform: "macos-arm64",
            components: ["updater": "1.2.3"],
            createdAt: "2026-05-31T00:00:00Z",
            artifacts: [],
            migrations: []
        )
        fileStore.directories.insert(source)
        fileStore.files[source.appendingPathComponent(Constants.Bundle.manifest)] = try JSONEncoder().encode(manifest)
        fileStore.files[source.appendingPathComponent(Constants.Bundle.checksums)] = Data()
        fileStore.files[source.appendingPathComponent(Constants.Bundle.signature)] = Data("signature".utf8)
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

private enum TestRuntimeBundleCompositionError: Error, Equatable {
    case vmStopFailed
    case cleanupFailed
    case rollbackFailed
    case restartFailed
}
