import Foundation
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeUninstallStateStoreTests: XCTestCase {
    func testWritePersistsExplicitUninstallStateDocument() throws {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-uninstall-state.json")
        let store = RuntimeUninstallStateStore(
            url: url,
            fileStore: fileStore,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        try store.write(
            state: .serviceStopBlocked,
            clean: true,
            message: "service stop blocked",
            blockers: ["vm-process-running:pid=123"]
        )

        XCTAssertTrue(fileStore.directories.contains(URL(fileURLWithPath: "/private/tmp")))
        let document = try JSONDecoder().decode(
            RuntimeUninstallStateDocument.self,
            from: XCTUnwrap(fileStore.files[url])
        )
        XCTAssertEqual(document.state, .serviceStopBlocked)
        XCTAssertEqual(document.clean, true)
        XCTAssertEqual(document.message, "service stop blocked")
        XCTAssertEqual(document.blockers, ["vm-process-running:pid=123"])
    }
}
