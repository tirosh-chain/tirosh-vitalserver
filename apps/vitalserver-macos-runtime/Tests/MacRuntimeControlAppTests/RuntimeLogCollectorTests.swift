import Foundation
import Core
import HostInfrastructure
@testable import MacHostRuntimeAdapter
@testable import MacRuntimeControlApp
import XCTest

final class RuntimeLogCollectorTests: XCTestCase {
    func testDefaultCopiesIncludeRuntimeServiceLogs() {
        let destinations = Set(RuntimeLogCopy.defaultCopies().map { $0.destination.lastPathComponent })
        let directoryDestinations = Set(RuntimeLogDirectoryCopy.defaultCopies().map { $0.destination.lastPathComponent })

        XCTAssertFalse(destinations.contains("proxy-nginx.access.log"))
        XCTAssertFalse(destinations.contains("proxy-nginx.error.log"))
        XCTAssertTrue(destinations.contains("launchd.out.log"))
        XCTAssertTrue(destinations.contains("launchd.err.log"))
        XCTAssertTrue(destinations.contains("proxy.out.log"))
        XCTAssertTrue(destinations.contains("proxy.err.log"))
        XCTAssertTrue(destinations.contains("watchdog.out.log"))
        XCTAssertTrue(directoryDestinations.contains("guest-observability"))
    }

    func testRefreshCopiesGuestObservabilityDirectory() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("run/guest-observability", isDirectory: true)
        let destination = root.appendingPathComponent("logs/guest/guest-observability", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "{\"ok\":true}\n".write(
            to: source.appendingPathComponent("latest.json"),
            atomically: true,
            encoding: .utf8
        )

        let collector = MacHostRuntimeLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [],
            directoryCopies: [
                RuntimeLogDirectoryCopy(source: source, destination: destination),
            ],
            rotatedCopySets: [],
            archiveDirectory: root.appendingPathComponent("archive")
        )

        try collector.refreshLogCollection()

        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("latest.json")),
            "{\"ok\":true}\n"
        )
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

        try collector.refreshLogCollection()

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

        try collector.refreshLogCollection()

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

        try collector.refreshLogCollection()

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

        try collector.refreshLogCollection()

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

        try collector.refreshLogCollection()

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

        try collector.refreshLogCollection(sourceID: .launcher)

        XCTAssertEqual(try String(contentsOf: launcherDestination), "launcher")
        XCTAssertFalse(FileManager.default.fileExists(atPath: proxyDestination.path))
    }

    func testTargetedRefreshCopiesVMDiagnosticLogSources() throws {
        let root = try temporaryDirectory()
        let sourceDirectory = root.appendingPathComponent("sources")
        let destinationDirectory = root.appendingPathComponent("central")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let launchOutputSource = sourceDirectory.appendingPathComponent("launchd.out.log")
        let launchErrorSource = sourceDirectory.appendingPathComponent("launchd.err.log")
        let watchdogSource = sourceDirectory.appendingPathComponent("watchdog.out.log")
        let launchOutputDestination = destinationDirectory.appendingPathComponent("launchd.out.log")
        let launchErrorDestination = destinationDirectory.appendingPathComponent("launchd.err.log")
        let watchdogDestination = destinationDirectory.appendingPathComponent("watchdog.out.log")
        try "launch output".write(to: launchOutputSource, atomically: true, encoding: .utf8)
        try "launch error".write(to: launchErrorSource, atomically: true, encoding: .utf8)
        try "watchdog".write(to: watchdogSource, atomically: true, encoding: .utf8)

        let collector = MacHostRuntimeLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [
                RuntimeLogCopy(source: launchOutputSource, destination: launchOutputDestination, archivePrefix: "launchd.out.log"),
                RuntimeLogCopy(source: launchErrorSource, destination: launchErrorDestination, archivePrefix: "launchd.err.log"),
                RuntimeLogCopy(source: watchdogSource, destination: watchdogDestination, archivePrefix: "watchdog.out.log"),
            ],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        try collector.refreshLogCollection(sourceID: .vmLaunchOutput)
        try collector.refreshLogCollection(sourceID: .vmLaunchError)
        try collector.refreshLogCollection(sourceID: .watchdog)

        XCTAssertEqual(try String(contentsOf: launchOutputDestination), "launch output")
        XCTAssertEqual(try String(contentsOf: launchErrorDestination), "launch error")
        XCTAssertEqual(try String(contentsOf: watchdogDestination), "watchdog")
    }

    func testRefreshPropagatesExistingLogReadFailure() {
        let source = URL(fileURLWithPath: "/source.log")
        let destination = URL(fileURLWithPath: "/central/source.log")
        let collector = MacHostRuntimeLogCollector(
            fileStore: FailingLogCollectionFileStore(existingFiles: [source, destination]),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            rotatedCopySets: []
        )

        XCTAssertThrowsError(try collector.refreshLogCollection())
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeLogCollectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class FailingLogCollectionFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let existingFiles: Set<URL>

    init(existingFiles: Set<URL>) {
        self.existingFiles = existingFiles
    }

    func fileExists(_ url: URL) -> Bool {
        existingFiles.contains(url)
    }

    func directoryExists(_ url: URL) -> Bool {
        false
    }

    func isExecutableFile(atPath path: String) -> Bool {
        false
    }

    func readData(_ url: URL) throws -> Data {
        throw CocoaError(.fileReadNoPermission)
    }

    func readUTF8Text(_ url: URL) throws -> String {
        throw CocoaError(.fileReadNoPermission)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        throw CocoaError(.fileReadNoPermission)
    }

    func modificationDate(_ url: URL) throws -> Date {
        throw CocoaError(.fileReadNoPermission)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}

    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        throw CocoaError(.fileReadNoPermission)
    }

    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        throw CocoaError(.fileReadNoPermission)
    }

    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        throw CocoaError(.fileReadNoPermission)
    }

    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        throw CocoaError(.fileReadNoPermission)
    }
}
