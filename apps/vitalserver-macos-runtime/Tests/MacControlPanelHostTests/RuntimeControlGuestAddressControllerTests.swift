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
        let controller = makeController()

        let state = try await controller.loadGuestAddressResource()

        XCTAssertEqual(state.state, .missing)
        XCTAssertNil(state.read)
        XCTAssertTrue(state.readError?.contains("Runtime endpoint document missing") == true)
    }

    func testPutAndLoadPreserveExplicitOwnerAddress() async throws {
        let controller = makeController()

        let put = try await controller.putGuestAddressResource(address: " 192.168.64.11\n")
        let loaded = try await controller.loadGuestAddressResource()

        XCTAssertEqual(put.state, .loaded)
        XCTAssertEqual(put.read?.loadedAddress, "192.168.64.11")
        XCTAssertEqual(put.read?.source, .platformAgent)
        XCTAssertEqual(loaded, put)
    }

    func testEmptyPutBecomesFailedResourceInsteadOfMissingOrLoaded() async throws {
        let controller = makeController()

        let put = try await controller.putGuestAddressResource(address: " \n")
        let loaded = try await controller.loadGuestAddressResource()

        XCTAssertEqual(put.state, .failed)
        XCTAssertNil(put.read)
        XCTAssertEqual(put.readError, "Runtime endpoint address is empty")
        XCTAssertEqual(loaded.state, .missing)
    }

    private func makeController() -> RuntimeControlGuestAddressController {
        let store = FileRuntimeGuestAddressResourceStore(
            documentURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("runtime-endpoint.json")
        )
        return RuntimeControlGuestAddressController(reader: store, writer: store)
    }
}
