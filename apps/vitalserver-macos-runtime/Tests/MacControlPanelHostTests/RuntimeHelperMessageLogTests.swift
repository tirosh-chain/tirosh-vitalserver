import XCTest
import Errors
@testable import MacControlPanelHost
@testable import InboundAdapters

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

    func testFileRuntimeHelperMessageLogStartsFreshSessionByDefault() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("helper-message.log")
        try "stale update failure\n".write(to: logURL, atomically: true, encoding: .utf8)

        let logger = FileRuntimeHelperMessageLog(
            url: logURL,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        logger.append("Ready")

        let text = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertFalse(text.contains("stale update failure"))
        XCTAssertEqual(text, "[2027-01-15T08:00:00Z] Ready\n")
    }

    func testFileRuntimeHelperMessageLogCanPreserveExistingLogWhenRequested() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("helper-message.log")
        try "previous\n".write(to: logURL, atomically: true, encoding: .utf8)

        let logger = FileRuntimeHelperMessageLog(
            url: logURL,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            resetExistingLog: false
        )
        logger.append("Ready")

        let text = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("previous\n"))
        XCTAssertTrue(text.contains("[2027-01-15T08:00:00Z] Ready"))
    }

    func testFileRuntimeHelperMessageLogDoesNotDeleteDirectoryAtLogPath() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("helper-message.log")
        try FileManager.default.createDirectory(at: logURL, withIntermediateDirectories: true)

        let logger = FileRuntimeHelperMessageLog(
            url: logURL,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        logger.append("Ready")

        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: logURL.path), [])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeHelperMessageLogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
