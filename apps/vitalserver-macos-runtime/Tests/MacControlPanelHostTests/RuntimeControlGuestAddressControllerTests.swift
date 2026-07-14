import Application
import Contracts
import Foundation
@testable import MacControlPanelHost
@testable import MacPlatformAgent
import OutboundAdapters
import XCTest

@MainActor
final class RuntimeControlGuestAddressControllerTests: XCTestCase {
    func testLoadReportsMissingDistinctly() async throws {
        let controller = try makeController()

        let state = try await controller.loadGuestAddressResource()

        XCTAssertEqual(state.state, .missing)
        XCTAssertNil(state.read)
        XCTAssertTrue(state.readError?.contains("SQLite state is missing") == true)
    }

    func testPutAndLoadPreserveExplicitOwnerAddress() async throws {
        let controller = try makeController(withLifecycle: true)

        let put = try await controller.putGuestAddressResource(address: " 192.168.64.11\n")
        let loaded = try await controller.loadGuestAddressResource()

        XCTAssertEqual(put.state, .loaded)
        XCTAssertEqual(put.read?.loadedAddress, "192.168.64.11")
        XCTAssertEqual(put.read?.source, .platformAgent)
        XCTAssertEqual(loaded, put)
    }

    func testEmptyPutBecomesFailedResourceInsteadOfMissingOrLoaded() async throws {
        let controller = try makeController(withLifecycle: true)

        let put = try await controller.putGuestAddressResource(address: " \n")
        let loaded = try await controller.loadGuestAddressResource()

        XCTAssertEqual(put.state, .failed)
        XCTAssertNil(put.read)
        XCTAssertTrue(put.readError?.contains("runtime endpoint field is invalid field=address") == true)
        XCTAssertEqual(loaded.state, .missing)
    }

    private func makeController(
        withLifecycle: Bool = false
    ) throws -> RuntimeControlGuestAddressController {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("runtime-state.sqlite")
        _ = try SQLiteHostRuntimeStateDatabase(url: databaseURL).initialize()
        if withLifecycle {
            let lifecycle = SQLiteRuntimeVMLifecycleStateRepository(
                databaseURL: databaseURL,
                transitionDecider: RuntimeVMLifecycleTransitionUseCase()
            )
            let startedAt = "2026-07-14T07:00:00Z"
            _ = try lifecycle.saveVMLifecycleState(RuntimeVMLifecycleStateMutation(
                document: RuntimeVMLifecycleDocument(
                    state: .starting,
                    operation: .startServices,
                    operationID: "operation-1",
                    bootID: "boot-1",
                    startedAt: startedAt,
                    updatedAt: startedAt,
                    deadlineAt: "2026-07-14T07:05:00Z"
                ),
                expectedRevision: nil
            ))
            _ = try lifecycle.saveVMLifecycleState(RuntimeVMLifecycleStateMutation(
                document: RuntimeVMLifecycleDocument(
                    state: .bootstrapping,
                    operation: .startServices,
                    operationID: "operation-1",
                    bootID: "boot-1",
                    startedAt: startedAt,
                    updatedAt: "2026-07-14T07:00:01Z",
                    deadlineAt: "2026-07-14T07:05:00Z"
                ),
                expectedRevision: 1
            ))
        }
        let store = SQLiteRuntimeGuestAddressResourceStore(
            databaseURL: databaseURL,
            lifecycleTransitionDecider: RuntimeVMLifecycleTransitionUseCase(),
            now: { Date(timeIntervalSince1970: 1_784_013_602) }
        )
        return RuntimeControlGuestAddressController(reader: store, writer: store)
    }
}
