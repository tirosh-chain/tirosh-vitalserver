import Foundation
import Core
import Contracts
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeBundleWorkflowTests: XCTestCase {
    func testPrepareApplyBundleLogsRecordsDirectoryAndRotationFailures() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.createDirectoryError = CocoaError(.fileWriteNoPermission)
        var logs: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            rotateRuntimeLogs: {
                throw LauncherError.runtimeOperationFailed("rotation failed")
            },
            log: { logs.append($0) }
        )

        workflow.prepareApplyBundleLogs()

        XCTAssertTrue(logs.contains { $0.contains("bundle apply log directory preparation failed") })
        XCTAssertTrue(logs.contains { $0.contains("bundle apply log rotation failed") })
    }

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

    private func makeWorkflow(
        fileStore: RuntimeFileStore,
        rotateRuntimeLogs: @escaping () throws -> Void = {},
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeBundleWorkflow {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        return RuntimeBundleWorkflow(
            context: RuntimeBundleWorkflowContext(
                installedPaths: installedPaths,
                bundlesDirectory: URL(fileURLWithPath: "/product/bundles"),
                backupsDirectory: URL(fileURLWithPath: "/product/backups"),
                logsDirectory: URL(fileURLWithPath: "/product/logs"),
                rootfsBase: URL(fileURLWithPath: "/product/rootfs-base.raw.gz"),
                vmDisk: URL(fileURLWithPath: "/product/vm-disk.img")
            ),
            operations: RuntimeBundleWorkflowOperations(
                fileStore: fileStore,
                runtimeHealthSnapshot: { Self.healthSnapshot() },
                rotateRuntimeLogs: rotateRuntimeLogs,
                rollback: { _ in },
                startRuntimeServices: { _ in },
                stopRuntimeServices: {},
                prepareGuestShutdownForUpdate: { _ in },
                clearGuestShutdownPreparation: {},
                isLaunchdLoaded: { _ in false },
                createBackup: { _ in URL(fileURLWithPath: "/product/backups/backup") },
                writeRuntimeStatus: { _, _, _ in },
                writeRuntimeProgress: { _ in },
                pruneOldRuntimeArtifacts: {},
                reasonText: { _ in "" },
                requireFreeSpace: { _, _, _ in },
                runProcess: { _, _ in RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "") },
                runRequired: { _, _ in },
                runProcessToFile: { _, _, _ in },
                replaceFile: { _, _ in },
                writeRuntimeVersion: { _, _ in },
                refreshCloudInitSeedIfNeeded: { _ in },
                activateGuestUpdateIfNeeded: { _ in },
                waitForHealth: { _ in },
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
}
