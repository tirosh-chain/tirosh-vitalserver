import Foundation
import HostInfrastructure
@testable import MacHostRuntimeAdapter
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeLogCollectorTests: XCTestCase {
    func testDefaultCopiesIncludeProxyNginxLogs() {
        let destinations = Set(RuntimeLogCopy.defaultCopies().map { $0.destination.lastPathComponent })

        XCTAssertTrue(destinations.contains("proxy-nginx.access.log"))
        XCTAssertTrue(destinations.contains("proxy-nginx.error.log"))
    }

    func testRefreshCopiesSourceLogToCentralDestination() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.log")
        let destination = root.appendingPathComponent("central/runtime/source.log")
        try "hello\nworld\n".write(to: source, atomically: true, encoding: .utf8)

        let collector = MacHostRuntimeLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        collector.refreshLogCollection()

        XCTAssertEqual(try String(contentsOf: destination), "hello\nworld\n")
    }

    func testRefreshAppendsNewBytesToExistingCentralLog() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.log")
        let destination = root.appendingPathComponent("central/runtime/source.log")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "line 1\n".write(to: source, atomically: true, encoding: .utf8)
        try "line 1\n".write(to: destination, atomically: true, encoding: .utf8)
        try "line 1\nline 2\n".write(to: source, atomically: true, encoding: .utf8)

        let collector = MacHostRuntimeLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        collector.refreshLogCollection()

        XCTAssertEqual(try String(contentsOf: destination), "line 1\nline 2\n")
    }

    func testRefreshReplacesCentralLogWhenExistingContentIsNotSourcePrefix() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.log")
        let destination = root.appendingPathComponent("central/runtime/source.log")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "old line\n".write(to: destination, atomically: true, encoding: .utf8)
        try "new line 1\nnew line 2\n".write(to: source, atomically: true, encoding: .utf8)

        let collector = MacHostRuntimeLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        collector.refreshLogCollection()

        XCTAssertEqual(try String(contentsOf: destination), "new line 1\nnew line 2\n")
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

        let collector = MacHostRuntimeLogCollector(
            fileStore: SystemRuntimeFileStore(),
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

        let collector = MacHostRuntimeLogCollector(
            fileStore: SystemRuntimeFileStore(),
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

    func testTargetedRefreshCopiesOnlySelectedLogSource() throws {
        let root = try temporaryDirectory()
        let sourceDirectory = root.appendingPathComponent("sources")
        let destinationDirectory = root.appendingPathComponent("central")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let launcherSource = sourceDirectory.appendingPathComponent("launcher.log")
        let proxySource = sourceDirectory.appendingPathComponent("proxy.err.log")
        let launcherDestination = destinationDirectory.appendingPathComponent("launcher.log")
        let proxyDestination = destinationDirectory.appendingPathComponent("proxy.err.log")
        try "launcher".write(to: launcherSource, atomically: true, encoding: .utf8)
        try "proxy".write(to: proxySource, atomically: true, encoding: .utf8)

        let collector = MacHostRuntimeLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [
                RuntimeLogCopy(source: launcherSource, destination: launcherDestination, archivePrefix: "launcher.log"),
                RuntimeLogCopy(source: proxySource, destination: proxyDestination, archivePrefix: "proxy.err.log"),
            ],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        collector.refreshLogCollection(sourceID: .launcher)

        XCTAssertEqual(try String(contentsOf: launcherDestination), "launcher")
        XCTAssertFalse(FileManager.default.fileExists(atPath: proxyDestination.path))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeLogCollectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
