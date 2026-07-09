import Contracts
import Foundation
@testable import MacControlPanelHost
import OutboundAdapters
import XCTest

@MainActor
final class RuntimeControlVMLifecycleControllerTests: XCTestCase {
    func testLoadReportsMissingDistinctly() async throws {
        let controller = RuntimeControlVMLifecycleController()

        let state = try await controller.loadVMLifecycleResource()

        XCTAssertEqual(state.state, .missing)
        XCTAssertNil(state.document)
        XCTAssertEqual(state.readError, "VM lifecycle document missing")
    }

    func testPutAndLoadPreserveExplicitDocument() async throws {
        let controller = RuntimeControlVMLifecycleController()
        let document = RuntimeVMLifecycleDocument(
            state: .bootstrapping,
            operation: .install,
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
}
