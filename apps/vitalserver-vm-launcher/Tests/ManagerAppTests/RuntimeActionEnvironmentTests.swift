import XCTest
@testable import ManagerApp

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

    func testCreatesDirectory() {
        let environment = SystemRuntimeActionEnvironment()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeActionEnvironmentTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        environment.createDirectory(at: url)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
