import Application
import Contracts
import Foundation
@testable import MacControlPanelHost
@testable import MacPlatformAgent
import OutboundAdapters
import XCTest

@MainActor
final class RuntimeControlVMLifecycleControllerTests: XCTestCase {
    func testLoadReportsMissingDistinctly() async throws {
        let controller = RuntimeControlVMLifecycleController(databaseURL: try temporaryDatabaseURL())

        let state = try await controller.loadVMLifecycleResource()

        XCTAssertEqual(state.state, .missing)
        XCTAssertNil(state.document)
        XCTAssertTrue(state.readError?.contains("SQLite state is missing") == true)
    }

    func testPutAndLoadPreserveExplicitDocument() async throws {
        let controller = RuntimeControlVMLifecycleController(databaseURL: try temporaryDatabaseURL())
        let starting = RuntimeVMLifecycleDocument(
            state: .starting,
            operation: .install,
            operationID: "operation-1",
            bootID: "boot-1",
            startedAt: "2026-07-09T01:00:00Z",
            updatedAt: "2026-07-09T01:00:00Z",
            deadlineAt: "2026-07-09T01:05:00Z",
            message: "starting"
        )
        _ = try await controller.putVMLifecycleResource(starting)
        let document = RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            operation: .install,
            operationID: "operation-1",
            bootID: "boot-1",
            startedAt: "2026-07-09T01:00:00Z",
            updatedAt: "2026-07-09T01:01:00Z",
            deadlineAt: nil,
            terminalReason: nil,
            message: "bootstrapping"
        )

        let put = try await controller.putVMLifecycleResource(document)
        let loaded = try await controller.loadVMLifecycleResource()

        XCTAssertEqual(put, .loaded(document))
        XCTAssertEqual(loaded, .loaded(document))
    }

    private func temporaryDatabaseURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeControlVMLifecycleControllerTests-\(UUID().uuidString)")
            .appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: url).initialize()
        return url
    }
}
