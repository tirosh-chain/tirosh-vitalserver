import XCTest
@testable import MacRuntimeControlApp

final class RuntimeHelperMessageLogTests: XCTestCase {
    func testFileRuntimeHelperMessageLogAppendsTimestampedEntries() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("helper-message.log")
        let logger = FileRuntimeHelperMessageLog(
            url: logURL,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        logger.append("Ready")
        logger.append("Update completed\nexitCode: 0")

        let text = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(text.contains("[2027-01-15T08:00:00Z] Ready"))
        XCTAssertTrue(text.contains("[2027-01-15T08:00:00Z] Update completed\n  exitCode: 0"))
    }

    func testFileRuntimeHelperMessageLogSkipsBlankMessages() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("helper-message.log")
        let logger = FileRuntimeHelperMessageLog(url: logURL)

        logger.append("  \n")

        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeHelperMessageLogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
