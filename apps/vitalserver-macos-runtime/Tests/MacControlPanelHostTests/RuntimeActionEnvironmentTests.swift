import XCTest
import Errors
@testable import OutboundAdapters
@testable import MacControlPanelHost
@testable import InboundAdapters

@MainActor
final class RuntimeActionEnvironmentTests: XCTestCase {
    func testWritesAndRemovesAdminPasswordFile() throws {
        let environment = SystemRuntimeActionEnvironment()

        let url = try environment.writeAdminPasswordFile("secret")
        defer { environment.removeItem(at: url) }

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "secret")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        environment.removeItem(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

}
