import Foundation
import HostInfrastructure
@testable import LocalManagement
@testable import MacManagerApp
import XCTest

final class RuntimeLogCollectorTests: XCTestCase {
    func testRefreshCopiesSourceLogToCentralDestination() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.log")
        let destination = root.appendingPathComponent("central/runtime/source.log")
        try "hello\nworld\n".write(to: source, atomically: true, encoding: .utf8)

        let collector = LocalRuntimeLogCollector(
            fileStore: LocalRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        collector.refreshLogCollection()

        XCTAssertEqual(try String(contentsOf: destination), "hello\nworld\n")
    }

    func testRefreshArchivesExistingCentralLogWhenItExceedsLimit() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.log")
        let destination = root.appendingPathComponent("central/source.log")
        let archiveDirectory = root.appendingPathComponent("archive")
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "old-log".write(to: destination, atomically: true, encoding: .utf8)

        let collector = LocalRuntimeLogCollector(
            fileStore: LocalRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            archiveDirectory: archiveDirectory,
            maxCentralLogBytes: 1,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        collector.refreshLogCollection()

        XCTAssertEqual(try String(contentsOf: destination), "new")
        let archivedFiles = try FileManager.default
            .contentsOfDirectory(
                at: archiveDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .flatMap {
                try FileManager.default.contentsOfDirectory(
                    at: $0,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            }
        XCTAssertEqual(archivedFiles.count, 1)
        XCTAssertTrue(archivedFiles[0].lastPathComponent.hasPrefix("source.log."))
        XCTAssertEqual(try String(contentsOf: archivedFiles[0]), "old-log")
    }

    func testRefreshCopiesRotatedContainerLogs() throws {
        let root = try temporaryDirectory()
        let sourceDirectory = root.appendingPathComponent("run")
        let destinationDirectory = root.appendingPathComponent("central/guest")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try "current".write(
            to: sourceDirectory.appendingPathComponent("container-logs.log"),
            atomically: true,
            encoding: .utf8
        )
        try "older".write(
            to: sourceDirectory.appendingPathComponent("container-logs.log.1"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored".write(
            to: sourceDirectory.appendingPathComponent("other.log.1"),
            atomically: true,
            encoding: .utf8
        )

        let collector = LocalRuntimeLogCollector(
            fileStore: LocalRuntimeFileStore(),
            copies: [
                RuntimeLogCopy(
                    source: sourceDirectory.appendingPathComponent("container-logs.log"),
                    destination: destinationDirectory.appendingPathComponent("container-logs.log"),
                    archivePrefix: "container-logs.log"
                ),
            ],
            rotatedCopySets: [
                RuntimeRotatedLogCopySet(
                    sourceDirectory: sourceDirectory,
                    sourceFilePrefix: "container-logs.log.",
                    destinationDirectory: destinationDirectory,
                    destinationFilePrefix: "container-logs.log.",
                    archivePrefix: "container-logs.log."
                ),
            ],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        collector.refreshLogCollection()

        XCTAssertEqual(
            try String(contentsOf: destinationDirectory.appendingPathComponent("container-logs.log")),
            "current"
        )
        XCTAssertEqual(
            try String(contentsOf: destinationDirectory.appendingPathComponent("container-logs.log.1")),
            "older"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destinationDirectory.appendingPathComponent("other.log.1").path
            )
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeLogCollectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
