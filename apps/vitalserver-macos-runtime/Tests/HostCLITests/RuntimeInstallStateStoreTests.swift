import Foundation
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeInstallStateStoreTests: XCTestCase {
    func testWritePersistsExplicitInstallStateDocument() throws {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install-state.json")
        let store = RuntimeInstallStateStore(
            url: url,
            fileStore: fileStore,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        try store.write(
            state: .stepStarted,
            mode: .full,
            currentStep: .provisionVMDisk,
            message: "install step started",
            blockers: []
        )

        XCTAssertTrue(fileStore.directories.contains(URL(fileURLWithPath: "/private/tmp")))
        let document = try JSONDecoder().decode(
            RuntimeInstallStateDocument.self,
            from: XCTUnwrap(fileStore.files[url])
        )
        XCTAssertEqual(document.state, .stepStarted)
        XCTAssertEqual(document.mode, .full)
        XCTAssertEqual(document.currentStep, .provisionVMDisk)
        XCTAssertEqual(document.message, "install step started")
        XCTAssertEqual(document.blockers, [])
    }
}
