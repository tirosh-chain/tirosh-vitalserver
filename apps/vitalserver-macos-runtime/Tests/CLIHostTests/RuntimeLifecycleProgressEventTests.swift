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
            runtimeStatusArtifactSink: MissingRuntimeStatusArtifactSink()
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

    func testWriteRuntimeProgressRecordsEventAndProgressWhenStatusDocumentIsMissing() throws {
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
            runtimeStatusArtifactSink: MissingRuntimeStatusArtifactSink()
        )

        try lifecycle.writeRuntimeProgress(
            .updating,
            operation: .applyBundle,
            step: .stopRuntimeServices,
            stepStatus: .started,
            phase: .running,
            message: "step started: stop-runtime-services"
        )

        let eventRead = JSONLRuntimeEventRepository(url: installedPaths.runtimeEvents).allResult()
        let progress = try JSONDecoder().decode(
            RuntimeProgressDocument.self,
            from: Data(contentsOf: installedPaths.runtimeProgress)
        )

        XCTAssertTrue(eventRead.issues.isEmpty)
        XCTAssertEqual(eventRead.events.count, 1)
        XCTAssertEqual(eventRead.events.first?.eventType, .progressUpdated)
        XCTAssertEqual(eventRead.events.first?.status, .updating)
        XCTAssertEqual(eventRead.events.first?.operation, .applyBundle)
        XCTAssertEqual(eventRead.events.first?.progress?.step, .stopRuntimeServices)
        XCTAssertEqual(eventRead.events.first?.progress?.stepStatus, .started)
        XCTAssertEqual(progress.operation, .applyBundle)
        XCTAssertEqual(progress.phase, .running)
        XCTAssertEqual(progress.step, .stopRuntimeServices)
        XCTAssertEqual(progress.stepStatus, .started)
        XCTAssertEqual(progress.message, "step started: stop-runtime-services")
    }

    func testRuntimeDataRestoreFailureWritesFailedProgress() throws {
        let fileStore = RuntimeFileStoreSpy()
        let statusArtifactSink = CapturingRuntimeStatusArtifactSink()
        let progressArtifactSink = CapturingRuntimeProgressArtifactSink()
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
            runtimeStatusArtifactSink: statusArtifactSink,
            runtimeProgressArtifactSink: progressArtifactSink,
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

        guard let status = statusArtifactSink.document else {
            return XCTFail("expected runtime status document after restore failure")
        }
        guard let progress = progressArtifactSink.document else {
            return XCTFail("expected runtime progress document after restore failure")
        }
        XCTAssertEqual(status.status, .healthy)
        XCTAssertEqual(progress.operation, .runtimeDataRestore)
        XCTAssertEqual(progress.step, .restoreRuntimeDataBackup)
        XCTAssertEqual(progress.stepStatus, .failed)
        XCTAssertEqual(progress.phase, .failed)
        XCTAssertTrue(progress.message.contains("missing-backup"))
    }
}

private final class CapturingRuntimeStatusArtifactSink: RuntimeStatusArtifactSink {
    var document: RuntimeStatusDocument?

    func save(_ document: RuntimeStatusDocument) throws {
        self.document = document
    }
}

private final class CapturingRuntimeProgressArtifactSink: RuntimeProgressArtifactSink {
    var document: RuntimeProgressDocument?

    func save(_ document: RuntimeProgressDocument) throws {
        self.document = document
    }
}

private struct MissingRuntimeStatusArtifactSink: RuntimeStatusArtifactSink {
    func save(_: RuntimeStatusDocument) throws {}
}
