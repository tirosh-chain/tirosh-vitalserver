import Foundation
@testable import HostCLI
import XCTest

final class RuntimeLogRotatorTests: XCTestCase {
    func testRotateMovesExistingGenerationsAndTruncatesCurrentLog() throws {
        let fileStore = RuntimeFileStoreSpy()
        let logsDirectory = URL(fileURLWithPath: "/runtime/logs")
        let current = logsDirectory.appendingPathComponent("launcher.log")
        let first = logsDirectory.appendingPathComponent("launcher.log.1")
        let second = logsDirectory.appendingPathComponent("launcher.log.2")
        fileStore.files[current] = Data("current".utf8)
        fileStore.files[first] = Data("first".utf8)
        fileStore.files[second] = Data("stale-second".utf8)
        var logs: [String] = []

        try RuntimeLogRotator(
            logsDirectory: logsDirectory,
            fileStore: fileStore,
            configuration: RuntimeLogRotationConfiguration(
                fileNames: ["launcher.log"],
                maxBytes: 3,
                keepCount: 2
            ),
            log: { logs.append($0) }
        ).rotate()

        XCTAssertEqual(fileStore.files[current], Data())
        XCTAssertEqual(fileStore.files[first], Data("current".utf8))
        XCTAssertEqual(fileStore.files[second], Data("first".utf8))
        XCTAssertTrue(logs.contains("rotated log file=/runtime/logs/launcher.log"))
    }

    func testRotateSkipsLogsBelowThreshold() throws {
        let fileStore = RuntimeFileStoreSpy()
        let logsDirectory = URL(fileURLWithPath: "/runtime/logs")
        let current = logsDirectory.appendingPathComponent("launcher.log")
        fileStore.files[current] = Data("ok".utf8)

        try RuntimeLogRotator(
            logsDirectory: logsDirectory,
            fileStore: fileStore,
            configuration: RuntimeLogRotationConfiguration(
                fileNames: ["launcher.log"],
                maxBytes: 3,
                keepCount: 2
            ),
            log: { _ in }
        ).rotate()

        XCTAssertEqual(fileStore.files[current], Data("ok".utf8))
        XCTAssertNil(fileStore.files[logsDirectory.appendingPathComponent("launcher.log.1")])
    }
}
