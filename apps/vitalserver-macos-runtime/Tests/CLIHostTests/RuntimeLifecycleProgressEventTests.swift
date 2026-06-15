import Foundation
import Bootstrap
import Application
import Contracts
import Domain
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeLifecycleProgressEventTests: XCTestCase {
    func testRuntimeLifecycleBuildsWorkflowCollaborators() {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-lifecycle-workflows-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: productRoot)
        }
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            runtimeStatusRepository: MissingRuntimeStatusRepository()
        )

        _ = lifecycle.runtimeInstallComposition()
        _ = lifecycle.runtimeStatusPrinter()
        _ = lifecycle.runtimeCloudInitSeedWriter()
        _ = lifecycle.runtimeHealthCheckRunner()
        _ = lifecycle.runtimeManagedOperationGuard()
        _ = lifecycle.runtimeWatchdogRunner()
        _ = lifecycle.runtimeConfigureRunner()
        _ = lifecycle.runtimeBundleComposition()
        _ = lifecycle.runtimeDatastoreRepairComposition()
        _ = lifecycle.runtimeVMDiskRepairComposition()
        _ = lifecycle.runtimeServiceControlRunner()
        _ = lifecycle.runtimeRollbackComposition()
    }

    func testWriteRuntimeProgressRecordsEventWhenStatusDocumentIsMissing() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-lifecycle-progress-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: productRoot)
        }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        try FileManager.default.createDirectory(
            at: installedPaths.vitalServerHelperBackupsDirectory,
            withIntermediateDirectories: true
        )
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            runtimeStatusRepository: MissingRuntimeStatusRepository()
        )

        XCTAssertThrowsError(try lifecycle.writeRuntimeProgress(
            .updating,
            operation: .applyBundle,
            step: .stopRuntimeServices,
            stepStatus: .started,
            phase: .running,
            message: "step started: stop-runtime-services"
        ))

        let eventRead = JSONLRuntimeEventRepository(url: installedPaths.runtimeEvents).allResult()

        XCTAssertTrue(eventRead.issues.isEmpty)
        XCTAssertEqual(eventRead.events.count, 1)
        XCTAssertEqual(eventRead.events.first?.eventType, .progressUpdated)
        XCTAssertEqual(eventRead.events.first?.status, .updating)
        XCTAssertEqual(eventRead.events.first?.operation, .applyBundle)
        XCTAssertEqual(eventRead.events.first?.progress?.step, .stopRuntimeServices)
        XCTAssertEqual(eventRead.events.first?.progress?.stepStatus, .started)
    }

    func testRuntimeDataRestoreFailureWritesFailedProgress() throws {
        let fileStore = RuntimeFileStoreSpy()
        let statusRepository = CapturingRuntimeStatusRepository()
        let productRoot = URL(fileURLWithPath: "/runtime-data-restore-progress")
        let installedPaths = InstalledRuntimePaths(productRoot: productRoot)
        fileStore.directories.formUnion([
            installedPaths.backupsDirectory,
            installedPaths.vitalServerHelperBackupsDirectory,
        ])
        let lifecycle = RuntimeLifecycle(
            paths: LauncherPaths(
                home: installedPaths.runtimeHome,
                installed: installedPaths,
                config: installedPaths.vmConfig,
                pidFile: installedPaths.pidFile
            ),
            runtimeStatusRepository: statusRepository,
            fileStore: fileStore
        )
        try lifecycle.writeRuntimeStatus(
            .healthy,
            operation: .status,
            message: "runtime ready"
        )

        let missingBackup = installedPaths.vitalServerHelperBackupsDirectory
            .appendingPathComponent("missing-backup")
        fileStore.directories.insert(missingBackup)
        XCTAssertThrowsError(try lifecycle.restoreRuntimeDataBackup(missingBackup))

        guard let status = statusRepository.document else {
            return XCTFail("expected runtime status document after restore failure")
        }
        XCTAssertEqual(status.status, .recovering)
        XCTAssertEqual(status.operation, .runtimeDataRestore)
        XCTAssertEqual(status.progress?.operation, .runtimeDataRestore)
        XCTAssertEqual(status.progress?.step, .restoreRuntimeDataBackup)
        XCTAssertEqual(status.progress?.stepStatus, .failed)
        XCTAssertEqual(status.progress?.phase, .failed)
        XCTAssertTrue(status.message.contains("VitalServer restore failed"))
        XCTAssertTrue(status.progress?.message.contains("missing-backup") == true)
    }
}

private final class CapturingRuntimeStatusRepository: RuntimeStatusRepository {
    var document: RuntimeStatusDocument?

    func loadResult() -> RuntimeStatusDocumentLoadResult {
        if let document {
            return .loaded(document)
        }
        return .missing
    }

    func save(_ document: RuntimeStatusDocument) throws {
        self.document = document
    }
}

private struct MissingRuntimeStatusRepository: RuntimeStatusRepository {
    func loadResult() -> RuntimeStatusDocumentLoadResult {
        .missing
    }

    func save(_: RuntimeStatusDocument) throws {}
}
