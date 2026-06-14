import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import Workflow
@testable import CLIHost
import XCTest
import Errors

final class RuntimeBundleCompositionTests: XCTestCase {
    func testRuntimeOperationLeaseDocumentHasBoundedExpiration() throws {
        let fixedDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-22T00:00:00Z"))
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: URL(fileURLWithPath: "/product"),
                installed: InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product")),
                config: URL(fileURLWithPath: "/product/vm/config.json"),
                pidFile: URL(fileURLWithPath: "/product/vm/run/vitalserver-vm.pid")
            ),
            clock: FixedRuntimeClock(now: fixedDate),
            fileStore: RuntimeFileStoreSpy()
        )

        let document = lifecycle.makeRuntimeOperationLeaseDocument(.applyBundle)

        XCTAssertEqual(document.operation, .applyBundle)
        XCTAssertEqual(document.startedAt, "2026-05-22T00:00:00Z")
        XCTAssertEqual(document.heartbeatAt, "2026-05-22T00:00:00Z")
        XCTAssertEqual(document.expiresAt, "2026-05-22T01:00:00Z")
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

    func testApplyBundleGuestShutdownStopFailureIsPropagatedAndLeaseIsReleased() throws {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/input/update-bundle")
        try writeEmptyBundle(at: source, to: fileStore)
        var events: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            startRuntimeServices: { _ in events.append("start") },
            prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff: { _ in
                events.append("shutdown-stop")
                throw TestRuntimeBundleCompositionError.vmStopFailed
            },
            isLaunchdLoaded: { service in service == .vm },
            rollback: { _ in events.append("rollback") },
            releaseOperationLease: { _ in events.append("release-lease") }
        )

        XCTAssertThrowsError(try workflow.applyBundle(source)) { error in
            XCTAssertEqual(error as? TestRuntimeBundleCompositionError, .vmStopFailed)
        }

        XCTAssertEqual(events, [
            "shutdown-stop",
            "rollback",
            "release-lease",
        ])
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

    func testApplyBundleAcquiresAndReleasesOperationLease() throws {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/input/update-bundle")
        try writeEmptyBundle(at: source, to: fileStore)
        var events: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            acquireOperationLease: { operation in
                events.append("acquire:\(operation.rawValue)")
                return RuntimeOperationLeaseDocument(
                    operationId: "lease-1",
                    operation: operation,
                    ownerPID: 123,
                    startedAt: "2026-05-22T00:00:00Z",
                    heartbeatAt: "2026-05-22T00:00:00Z",
                    expiresAt: nil,
                    message: nil
                )
            },
            heartbeatOperationLease: { lease in
                events.append("heartbeat:\(lease.operationId)")
            },
            releaseOperationLease: { lease in
                events.append("release:\(lease.operationId)")
            }
        )

        try workflow.applyBundle(source)

        XCTAssertEqual(events.first, "acquire:apply-bundle")
        XCTAssertEqual(events.last, "release:lease-1")
        XCTAssertGreaterThan(events.filter { $0 == "heartbeat:lease-1" }.count, 0)
    }

    func testApplyBundleLogsLeaseReleaseFailureWithoutHidingApplyFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/input/update-bundle")
        try writeEmptyBundle(at: source, to: fileStore)
        var logs: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            stopRuntimeServices: {
                throw TestRuntimeBundleCompositionError.vmStopFailed
            },
            releaseOperationLease: { _ in
                throw TestRuntimeBundleCompositionError.cleanupFailed
            },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try workflow.applyBundle(source)) { error in
            XCTAssertEqual(error as? TestRuntimeBundleCompositionError, .vmStopFailed)
        }
        XCTAssertTrue(logs.contains { $0.contains("runtime operation lease release failed") })
        XCTAssertTrue(logs.contains { $0.contains("operation=apply-bundle") })
        XCTAssertTrue(logs.contains { $0.contains("error=cleanupFailed") })
    }

    private func makeWorkflow(
        fileStore: RuntimeFileStore,
        startRuntimeServices: @escaping (RuntimeServiceRestartPolicy) throws -> Void = { _ in },
        stopRuntimeServices: @escaping () throws -> Void = {},
        prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff: @escaping (UpdateBundleManifest) throws -> Void = { _ in },
        isLaunchdLoaded: @escaping (RuntimeManagedService) -> Bool = { _ in false },
        rollback: @escaping (URL?) throws -> Void = { _ in },
        rotateRuntimeLogs: @escaping () throws -> Void = {},
        acquireOperationLease: @escaping (RuntimeOperation) throws -> RuntimeOperationLeaseDocument = { operation in
            RuntimeOperationLeaseDocument(
                operationId: UUID().uuidString,
                operation: operation,
                ownerPID: 123,
                startedAt: "2026-05-22T00:00:00Z",
                heartbeatAt: "2026-05-22T00:00:00Z",
                expiresAt: nil,
                message: nil
            )
        },
        heartbeatOperationLease: @escaping (RuntimeOperationLeaseDocument) throws -> Void = { _ in },
        releaseOperationLease: @escaping (RuntimeOperationLeaseDocument) throws -> Void = { _ in },
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
                prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff: prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff,
                isLaunchdLoaded: isLaunchdLoaded,
                createBackup: { _ in URL(fileURLWithPath: "/product/backups/backup") },
                statusReporter: RuntimeWorkflowStatusReporter(
                    writeStatus: { _, _, _ in },
                    writeProgress: { _ in },
                    describeError: { _ in "unexpected" },
                    log: log
                ),
                pruneOldRuntimeArtifacts: {},
                materializeBundle: { url in
                    guard fileStore.directoryExists(url) else {
                        throw LauncherError.missingFile(url.path)
                    }
                    return RuntimeMaterializedBundle(bundleURL: url, temporaryRoot: nil)
                },
                executeMaterializationCleanupPlan: { plan in
                    switch plan {
                    case .none:
                        return
                    case .cleanupTemporaryRoot(let temporaryRoot):
                        do {
                            try fileStore.removeItem(at: temporaryRoot)
                        } catch {
                            log("bundle temporary directory cleanup failed path=\(temporaryRoot.path) error=\(RuntimeErrorDescription.describe(error))")
                        }
                    }
                },
                removeMaterializedBundleTemporaryRoot: { temporaryRoot in
                    do {
                        try fileStore.removeItem(at: temporaryRoot)
                    } catch {
                        log("bundle temporary directory cleanup failed path=\(temporaryRoot.path) error=\(RuntimeErrorDescription.describe(error))")
                    }
                },
                stageMaterializedBundle: { input in
                    try RuntimeBundleStager(
                        context: RuntimeBundleStagingContext(
                            bundlesDirectory: URL(fileURLWithPath: "/product/bundles"),
                            updateFreeSpaceMarginBytes: Constants.Runtime.updateFreeSpaceMarginBytes
                        ),
                        operations: RuntimeBundleStagingOperations(
                            directorySize: { url in
                                try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
                            },
                            compressedSourceSize: { url in
                                fileStore.fileExists(url) ? try fileStore.fileSize(url) : 0
                            },
                            destinationState: { url in
                                fileStore.pathState(at: url)
                            },
                            createDirectory: { url, withIntermediateDirectories in
                                try fileStore.createDirectory(
                                    at: url,
                                    withIntermediateDirectories: withIntermediateDirectories
                                )
                            },
                            removeItem: { url in
                                try fileStore.removeItem(at: url)
                            },
                            copyItem: { source, destination in
                                try fileStore.copyItem(at: source, to: destination)
                            },
                            requireFreeSpace: { _, _, _ in },
                            log: log
                        )
                    ).stage(input: input)
                },
                validateUpdateArtifactPayload: { _, _ in },
                replaceUpdateArtifacts: { _, _ in },
                runMigrations: { _, _ in },
                requireFreeSpace: { _, _, _ in },
                directorySize: { url in
                    try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
                },
                replaceFile: { _, _ in },
                writeRuntimeVersion: { _, _ in },
                refreshCloudInitSeedIfNeeded: { _ in },
                activateGuestUpdateIfNeeded: { _ in },
                waitForHealth: { _ in },
                requireGuestCapability: { _ in },
                acquireOperationLease: acquireOperationLease,
                heartbeatOperationLease: heartbeatOperationLease,
                releaseOperationLease: releaseOperationLease,
                log: log
            )
        )
    }

    private static func healthSnapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: .executable,
            proxyExecutable: .executable,
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
            channel: Constants.launcherChannel,
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

private struct FixedRuntimeClock: RuntimeClock {
    let now: Date
}

private enum TestRuntimeBundleCompositionError: Error, Equatable {
    case vmStopFailed
    case cleanupFailed
    case rollbackFailed
    case restartFailed
}
