import Application
import Contracts
import Foundation
@testable import MacControlPanelHost
import XCTest

@MainActor
final class RuntimeControlGuestAddressControllerTests: XCTestCase {
    func testLoadReportsMissingDistinctly() async throws {
        let controller = RuntimeControlGuestAddressController()

        let state = try await controller.loadGuestAddressResource()

        XCTAssertEqual(state.state, .missing)
        XCTAssertNil(state.read)
        XCTAssertEqual(state.readError, "Guest address resource missing")
    }

    func testPutAndLoadPreserveExplicitOwnerAddress() async throws {
        let controller = RuntimeControlGuestAddressController()

        let put = try await controller.putGuestAddressResource(address: " 192.168.64.11\n")
        let loaded = try await controller.loadGuestAddressResource()

        XCTAssertEqual(put.state, .loaded)
        XCTAssertEqual(put.read?.loadedAddress, "192.168.64.11")
        XCTAssertEqual(put.read?.source, .runtimeControlAPI)
        XCTAssertEqual(loaded, put)
    }

    func testEmptyPutBecomesFailedResourceInsteadOfMissingOrLoaded() async throws {
        let controller = RuntimeControlGuestAddressController()

        let put = try await controller.putGuestAddressResource(address: " \n")
        let loaded = try await controller.loadGuestAddressResource()

        XCTAssertEqual(put.state, .failed)
        XCTAssertNil(put.read)
        XCTAssertEqual(put.readError, "Guest address is empty")
        XCTAssertEqual(loaded, put)
    }
}
