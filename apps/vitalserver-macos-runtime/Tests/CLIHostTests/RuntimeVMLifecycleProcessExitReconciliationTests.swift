import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeVMLifecycleProcessExitReconciliationTests: XCTestCase {
    func testObservedProcessExitRecordsTerminalFailureBeforeNextRun() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-process-exit-reconciliation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = InstalledRuntimePaths(productRoot: root)
        let paths = LauncherPaths(
            home: installed.runtimeHome,
            installed: installed,
            config: installed.vmConfig,
            pidFile: installed.pidFile
        )
        let lifecycle = RuntimeLifecycle(paths: paths)
        try lifecycle.initializeHostStateStore()
        let owner = SQLiteRuntimeVMLifecycleResourceStore(
            databaseURL: installed.runtimeStateDatabase,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase(),
            now: { Date(timeIntervalSince1970: 100) },
            operationID: { "operation-1" },
            bootID: { "boot-1" }
        )
        _ = try owner.writeVMLifecycleResource(
            state: .starting,
            operation: .startServices,
            message: "start"
        )
        _ = try owner.writeVMLifecycleResource(
            state: .stopping,
            message: "stop requested"
        )
        var logs: [String] = []

        try RuntimeVMLifecycleProcessExitReconciler.reconcile(
            expectedVMProcessID: 42,
            paths: paths,
            log: { logs.append($0) }
        )

        let state = owner.loadVMLifecycleResource()
        XCTAssertEqual(state.document?.state, .failed)
        XCTAssertEqual(
            state.document?.terminalReason,
            .processExitedWithoutTerminalState
        )
        XCTAssertEqual(
            state.document?.message,
            "VM process exited without terminal lifecycle state pid=42 previousState=stopping"
        )
        XCTAssertEqual(logs, [
            "VM process exited without terminal lifecycle state pid=42 previousState=stopping"
        ])
    }
    func testCompletedServiceStopRecordsTerminalFailureForPreviouslyStuckLifecycle() throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let owner = context.owner
        _ = try owner.putVMLifecycleResource(RuntimeVMLifecycleDocument(
            state: .starting,
            operation: .configure,
            operationID: "settings-2",
            bootID: "boot-2",
            startedAt: "2026-07-15T05:20:00Z",
            updatedAt: "2026-07-15T05:20:00Z",
            deadlineAt: "2026-07-15T05:25:00Z"
        ))
        _ = try owner.putVMLifecycleResource(RuntimeVMLifecycleDocument(
            state: .stopping,
            operation: .configure,
            operationID: "settings-2",
            bootID: "boot-2",
            startedAt: "2026-07-15T05:20:00Z",
            updatedAt: "2026-07-15T05:25:00Z"
        ))

        try RuntimeVMLifecycleProcessExitReconciler.reconcileAfterServiceStop(
            paths: context.paths,
            log: { _ in }
        )

        let read = owner.loadVMLifecycleResource()
        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.document?.state, .failed)
        XCTAssertEqual(
            read.document?.terminalReason,
            .serviceStoppedWithoutTerminalState
        )
        XCTAssertEqual(
            read.document?.message,
            "VM service stopped without terminal lifecycle state previousState=stopping"
        )
    }

    func testCompletedServiceStopPreservesExplicitlyMissingLifecycle() throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        var logs: [String] = []

        try RuntimeVMLifecycleProcessExitReconciler.reconcileAfterServiceStop(
            paths: context.paths,
            log: { logs.append($0) }
        )

        let read = context.owner.loadVMLifecycleResource()
        XCTAssertEqual(read.state, .missing)
        XCTAssertNil(read.document)
        XCTAssertEqual(logs, [
            "VM lifecycle is explicitly missing after service stop; no prior VM run requires reconciliation"
        ])
    }

    private func makeContext() throws -> (
        root: URL,
        paths: LauncherPaths,
        owner: SQLiteRuntimeVMLifecycleResourceStore
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-service-stop-reconciliation-\(UUID().uuidString)")
        let installed = InstalledRuntimePaths(productRoot: root)
        let paths = LauncherPaths(
            home: installed.runtimeHome,
            installed: installed,
            config: installed.vmConfig,
            pidFile: installed.pidFile
        )
        let lifecycle = RuntimeLifecycle(paths: paths)
        try lifecycle.initializeHostStateStore()
        let owner = SQLiteRuntimeVMLifecycleResourceStore(
            databaseURL: installed.runtimeStateDatabase,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase(),
            now: { Date(timeIntervalSince1970: 100) },
            operationID: { "operation-2" },
            bootID: { "boot-2" }
        )
        return (root, paths, owner)
    }
}
