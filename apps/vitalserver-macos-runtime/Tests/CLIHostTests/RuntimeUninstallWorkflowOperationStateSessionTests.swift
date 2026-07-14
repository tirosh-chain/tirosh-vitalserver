import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters
import Workflow
@testable import CLIHost
import XCTest

final class RuntimeUninstallWorkflowOperationStateSessionTests: XCTestCase {
    func testRepositoryContinuesFromRelocatedProductRootAndCommitsTerminalState() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("uninstall-state-session-\(UUID().uuidString)", isDirectory: true)
        let productRoot = temporaryRoot.appendingPathComponent("product", isDirectory: true)
        let relocatedRoot = temporaryRoot.appendingPathComponent(".product.uninstall-operation-1", isDirectory: true)
        let databaseURL = productRoot.appendingPathComponent("vm/runtime/runtime-state.sqlite")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        var timestamp = 0.0
        let session = RuntimeUninstallWorkflowOperationStateSession(
            operationID: "operation-1",
            databaseURL: databaseURL,
            now: {
                timestamp += 1
                return Date(timeIntervalSince1970: timestamp)
            },
            ownerPID: 123,
            leaseDurationSeconds: 1_800,
            repositoryFactory: { SQLiteRuntimeWorkflowOperationStateRepository(databaseURL: $0) },
            leaseOwnerFactory: { SQLiteRuntimeOperationLeaseRepository(databaseURL: $0) }
        )
        let writer = session.writer()

        try writer.acquireOperationLease()
        try writer.writeState(.started, true, "uninstall started", [])
        try writer.writeState(.filesRemovalStarted, true, "file removal started", [])
        try FileManager.default.moveItem(at: productRoot, to: relocatedRoot)
        try writer.relocateProductRoot(productRoot, relocatedRoot)
        try writer.writeState(.receiptsForgetStarted, true, "receipt forget started", [])
        try writer.writeState(.completed, true, "uninstall completed", [])
        try writer.releaseOperationLease()

        let relocatedDatabaseURL = relocatedRoot.appendingPathComponent("vm/runtime/runtime-state.sqlite")
        switch SQLiteRuntimeWorkflowOperationStateRepository(
            databaseURL: relocatedDatabaseURL
        ).loadOperationState(operationID: "operation-1") {
        case .loaded(let state):
            XCTAssertEqual(state.operation, .uninstall)
            XCTAssertEqual(state.phase, .completed)
            XCTAssertEqual(state.message, "uninstall completed")
            XCTAssertEqual(state.revision, 4)
        case .missing:
            XCTFail("relocated workflow operation state is missing")
        case .failed(let reason):
            XCTFail("relocated workflow operation state read failed: \(reason)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertEqual(
            SQLiteRuntimeOperationLeaseRepository(
                databaseURL: relocatedDatabaseURL
            ).loadOperationLease(),
            .missing
        )
    }

    func testRelocationRejectsDatabaseOutsideProductRoot() throws {
        let repository = RuntimeWorkflowOperationStateRepositorySpy()
        let session = RuntimeUninstallWorkflowOperationStateSession(
            operationID: "operation-1",
            databaseURL: URL(fileURLWithPath: "/other/runtime-state.sqlite"),
            now: { Date(timeIntervalSince1970: 0) },
            ownerPID: 123,
            leaseDurationSeconds: 1_800,
            repositoryFactory: { _ in repository },
            leaseOwnerFactory: { _ in RuntimeOperationLeaseOwnerSpy() }
        )
        let writer = session.writer()
        try writer.acquireOperationLease()
        try writer.writeState(.started, true, "uninstall started", [])

        XCTAssertThrowsError(
            try writer.relocateProductRoot(
                URL(fileURLWithPath: "/product"),
                URL(fileURLWithPath: "/.product.uninstall-operation-1")
            )
        ) { error in
            XCTAssertEqual(
                error as? RuntimeUninstallWorkflowOperationStateSessionError,
                .databaseOutsideProductRoot(
                    database: "/other/runtime-state.sqlite",
                    productRoot: "/product"
                )
            )
        }
    }

    func testCompletedUninstallDisposalAllowsReinstallWithNewEmptyHostStateIdentity() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("uninstall-reinstall-session-\(UUID().uuidString)", isDirectory: true)
        let productRoot = temporaryRoot.appendingPathComponent("product", isDirectory: true)
        let relocatedRoot = temporaryRoot.appendingPathComponent(".product.uninstall-operation-old", isDirectory: true)
        let databaseURL = productRoot.appendingPathComponent("vm/runtime/runtime-state.sqlite")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        _ = try SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "database-old" }
        ).initialize()
        let session = RuntimeUninstallWorkflowOperationStateSession(
            operationID: "operation-old",
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1) },
            ownerPID: 123,
            leaseDurationSeconds: 1_800,
            repositoryFactory: { SQLiteRuntimeWorkflowOperationStateRepository(databaseURL: $0) },
            leaseOwnerFactory: { SQLiteRuntimeOperationLeaseRepository(databaseURL: $0) }
        )
        let writer = session.writer()
        try writer.acquireOperationLease()
        try writer.writeState(.started, false, "uninstall started", [])
        try writer.writeState(.filesRemovalStarted, false, "file removal started", [])
        try FileManager.default.moveItem(at: productRoot, to: relocatedRoot)
        try writer.relocateProductRoot(productRoot, relocatedRoot)
        try writer.writeState(.receiptsForgetStarted, false, "receipt forget started", [])
        try writer.writeState(.completed, false, "uninstall completed", [])
        try writer.releaseOperationLease()
        try FileManager.default.removeItem(at: relocatedRoot)

        let reinstalled = try SQLiteHostRuntimeStateDatabase(
            url: databaseURL,
            databaseID: { "database-new" }
        ).initialize()

        XCTAssertEqual(reinstalled.databaseID, "database-new")
        XCTAssertEqual(
            SQLiteRuntimeWorkflowOperationStateRepository(databaseURL: databaseURL)
                .loadOperationState(operationID: "operation-old"),
            .missing
        )
        XCTAssertEqual(
            SQLiteRuntimeOperationLeaseRepository(databaseURL: databaseURL).loadOperationLease(),
            .missing
        )
        XCTAssertEqual(
            SQLiteRuntimeHostSettingsRepository(
                databaseURL: databaseURL,
                transitionDecider: RuntimeHostSettingsActivationUseCase()
            ).loadHostSettings(),
            .missing
        )
        XCTAssertEqual(
            SQLiteRuntimeVMLifecycleResourceStore(
                databaseURL: databaseURL,
                transitionDecider: RuntimeVMLifecycleTransitionUseCase()
            ).loadVMLifecycleResource(),
            .missing(readError: "VM lifecycle SQLite state is missing")
        )
        XCTAssertEqual(
            SQLiteRuntimeGuestAddressResourceStore(
                databaseURL: databaseURL,
                lifecycleTransitionDecider: RuntimeVMLifecycleTransitionUseCase()
            ).readGuestAddress(),
            .missing("Runtime endpoint SQLite state is missing")
        )
    }
}

private final class RuntimeOperationLeaseOwnerSpy: RuntimeOperationLeaseOwner {
    private var lease: RuntimeOperationLeaseDocument?

    func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        lease.map(RuntimeOperationLeaseLoadResult.loaded) ?? .missing
    }

    func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        lease = document
    }

    func heartbeat(operationId: String, heartbeatAt: String, expiresAt: String?) throws {}

    func release(operationId: String) throws {
        lease = nil
    }
}
