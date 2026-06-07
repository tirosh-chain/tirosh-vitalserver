import Foundation
import Application
import Contracts
import Domain
import OutboundAdapters
import RuntimeControl
@testable import OutboundAdapters
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeLogCollectorTests: XCTestCase {
    func testLogCollectionPolicyRotatesFromExplicitNowWithoutImplicitSystemDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rules = RuntimeLogCollectionDecisionRules(calendar: calendar)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sameDay = now.addingTimeInterval(-60)
        let previousDay = now.addingTimeInterval(-86_400)

        XCTAssertFalse(rules.shouldRotateCentralLog(RuntimeLogCollectionRotationInput(
            destinationPresent: true,
            fileSize: 10,
            modificationDate: sameDay,
            now: now,
            maxCentralLogBytes: 100
        )))
        XCTAssertTrue(rules.shouldRotateCentralLog(RuntimeLogCollectionRotationInput(
            destinationPresent: true,
            fileSize: 10,
            modificationDate: previousDay,
            now: now,
            maxCentralLogBytes: 100
        )))
        XCTAssertTrue(rules.shouldRotateCentralLog(RuntimeLogCollectionRotationInput(
            destinationPresent: true,
            fileSize: 100,
            modificationDate: sameDay,
            now: now,
            maxCentralLogBytes: 100
        )))
        XCTAssertFalse(rules.shouldRotateCentralLog(RuntimeLogCollectionRotationInput(
            destinationPresent: false,
            fileSize: 100,
            modificationDate: previousDay,
            now: now,
            maxCentralLogBytes: 100
        )))
    }

    func testLogCollectionPolicyKeepsAppendDecisionPure() {
        let rules = RuntimeLogCollectionDecisionRules()

        XCTAssertTrue(rules.canAppendCopy(RuntimeLogCollectionAppendInput(
            destinationPresent: true,
            sourceSize: 12,
            destinationSize: 6,
            sourceMatchesDestinationTail: true
        )))
        XCTAssertFalse(rules.canAppendCopy(RuntimeLogCollectionAppendInput(
            destinationPresent: true,
            sourceSize: 12,
            destinationSize: 6,
            sourceMatchesDestinationTail: false
        )))
        XCTAssertFalse(rules.canAppendCopy(RuntimeLogCollectionAppendInput(
            destinationPresent: false,
            sourceSize: 12,
            destinationSize: 0,
            sourceMatchesDestinationTail: true
        )))
    }

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

        let collector = MacRuntimeControlLogCollector(
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

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: [],
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
        let touchDate = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: touchDate], ofItemAtPath: destination.path)

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: [],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { touchDate }
        )

        try collector.refreshLogCollection()

        XCTAssertEqual(try String(contentsOf: destination), "line 1\nline 2\n")
    }

    func testRefreshAppendsUsingInjectedFileStoreWithoutDirectFileHandles() throws {
        let source = URL(fileURLWithPath: "/virtual/source.log")
        let destination = URL(fileURLWithPath: "/virtual/central/source.log")
        let fileStore = InMemoryLogCollectionFileStore(
            files: [
                source: Data("line 1\nline 2\n".utf8),
                destination: Data("line 1\n".utf8),
            ],
            modificationDates: [
                source: Date(timeIntervalSince1970: 2),
                destination: Date(timeIntervalSince1970: 1),
            ]
        )
        var touched: [(URL, Date)] = []
        let touchDate = Date(timeIntervalSince1970: 3)
        let collector = MacRuntimeControlLogCollector(
            fileStore: fileStore,
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: [],
            now: { touchDate },
            setModificationDate: { url, date in
                touched.append((url, date))
            }
        )

        try collector.refreshLogCollection()

        XCTAssertEqual(fileStore.files[destination], Data("line 1\nline 2\n".utf8))
        XCTAssertEqual(touched.map(\.0), [destination])
        XCTAssertEqual(touched.map(\.1), [touchDate])
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
        let touchDate = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: touchDate], ofItemAtPath: destination.path)

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: [],
            archiveDirectory: root.appendingPathComponent("archive"),
            now: { touchDate }
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

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: [],
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

    func testRefreshArchivesExistingCentralLogWhenItIsOlderThanExplicitNowDay() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.log")
        let destination = root.appendingPathComponent("central/source.log")
        let archiveDirectory = root.appendingPathComponent("archive")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previousDay = now.addingTimeInterval(-86_400)
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "old-log".write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: previousDay], ofItemAtPath: destination.path)

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: [],
            archiveDirectory: archiveDirectory,
            maxCentralLogBytes: 1_000,
            now: { now }
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
        XCTAssertEqual(try String(contentsOf: archivedFiles[0]), "old-log")
    }

    func testRefreshUsesExplicitArchiveCollisionIDWhenTimestampCandidatesAreExhausted() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.log")
        let destination = root.appendingPathComponent("central/source.log")
        let archiveDirectory = root.appendingPathComponent("archive")
        let archiveDate = Date(timeIntervalSince1970: 1_800_000_000)
        let archiveDayDirectory = archiveDirectory.appendingPathComponent(archiveTestDay(archiveDate))
        let archiveBaseName = "source.log.\(archiveTestTimestamp(archiveDate))"
        let archiveBase = archiveDayDirectory.appendingPathComponent(archiveBaseName)
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: archiveDayDirectory, withIntermediateDirectories: true)
        try "old-log".write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: archiveDate], ofItemAtPath: destination.path)
        try "collision".write(to: archiveBase, atomically: true, encoding: .utf8)
        for index in 1...999 {
            try "collision \(index)"
                .write(to: archiveDayDirectory.appendingPathComponent("\(archiveBaseName).\(index)"), atomically: true, encoding: .utf8)
        }

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: [],
            archiveDirectory: archiveDirectory,
            maxCentralLogBytes: 1,
            archiveCollisionID: { "collision-id" }
        )

        try collector.refreshLogCollection()

        XCTAssertEqual(try String(contentsOf: destination), "new")
        XCTAssertEqual(
            try String(contentsOf: archiveDayDirectory.appendingPathComponent("\(archiveBaseName).collision-id")),
            "old-log"
        )
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

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [
                RuntimeLogCopy(
                    source: sourceDirectory.appendingPathComponent("container-logs.log"),
                    destination: destinationDirectory.appendingPathComponent("container-logs.log"),
                    archivePrefix: "container-logs.log"
                ),
            ],
            directoryCopies: [],
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

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [
                RuntimeLogCopy(source: launcherSource, destination: launcherDestination, archivePrefix: "launcher.log"),
                RuntimeLogCopy(source: proxySource, destination: proxyDestination, archivePrefix: "proxy.err.log"),
            ],
            directoryCopies: [],
            rotatedCopySets: [],
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

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [
                RuntimeLogCopy(source: launchOutputSource, destination: launchOutputDestination, archivePrefix: "launchd.out.log"),
                RuntimeLogCopy(source: launchErrorSource, destination: launchErrorDestination, archivePrefix: "launchd.err.log"),
                RuntimeLogCopy(source: watchdogSource, destination: watchdogDestination, archivePrefix: "watchdog.out.log"),
            ],
            directoryCopies: [],
            rotatedCopySets: [],
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
        let collector = MacRuntimeControlLogCollector(
            fileStore: FailingLogCollectionFileStore(existingFiles: [source, destination]),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: []
        )

        XCTAssertThrowsError(try collector.refreshLogCollection())
    }

    func testRefreshFailsWhenLogSourceInspectionFails() {
        let source = URL(fileURLWithPath: "/source.log")
        let destination = URL(fileURLWithPath: "/central/source.log")
        let collector = MacRuntimeControlLogCollector(
            fileStore: PathStateLogCollectionFileStore(pathStates: [
                source.path: .inspectFailed("permission denied"),
            ]),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: []
        )

        XCTAssertThrowsError(try collector.refreshLogCollection()) { error in
            XCTAssertEqual(
                error as? RuntimeControlLogCollectorError,
                .pathInspectionFailed(path: source.path, reason: "permission denied")
            )
        }
    }

    func testRefreshFailsWhenCentralLogDestinationIsDirectory() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source.log")
        let destination = root.appendingPathComponent("central/source.log")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [RuntimeLogCopy(source: source, destination: destination, archivePrefix: "source.log")],
            directoryCopies: [],
            rotatedCopySets: [],
            archiveDirectory: root.appendingPathComponent("archive")
        )

        XCTAssertThrowsError(try collector.refreshLogCollection()) { error in
            XCTAssertEqual(
                error as? RuntimeControlLogCollectorError,
                .unexpectedPathState(path: destination.path, state: "directory")
            )
        }
    }

    func testRefreshFailsWhenDirectoryCopySourceIsFile() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("guest-observability")
        let destination = root.appendingPathComponent("central/guest-observability")
        try "not-directory".write(to: source, atomically: true, encoding: .utf8)

        let collector = MacRuntimeControlLogCollector(
            fileStore: SystemRuntimeFileStore(),
            copies: [],
            directoryCopies: [
                RuntimeLogDirectoryCopy(source: source, destination: destination),
            ],
            rotatedCopySets: [],
            archiveDirectory: root.appendingPathComponent("archive")
        )

        XCTAssertThrowsError(try collector.refreshLogCollection()) { error in
            XCTAssertEqual(
                error as? RuntimeControlLogCollectorError,
                .unexpectedPathState(path: source.path, state: "file")
            )
        }
    }

    func testRefreshFailsWhenDirectoryCopyDestinationIsOtherPathState() {
        let source = URL(fileURLWithPath: "/source/guest-observability")
        let destination = URL(fileURLWithPath: "/central/guest-observability")
        let collector = MacRuntimeControlLogCollector(
            fileStore: PathStateLogCollectionFileStore(pathStates: [
                source.path: .directory,
                destination.path: .other("socket"),
            ]),
            copies: [],
            directoryCopies: [
                RuntimeLogDirectoryCopy(source: source, destination: destination),
            ],
            rotatedCopySets: []
        )

        XCTAssertThrowsError(try collector.refreshLogCollection()) { error in
            XCTAssertEqual(
                error as? RuntimeControlLogCollectorError,
                .unexpectedPathState(path: destination.path, state: "other: socket")
            )
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeLogCollectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func archiveTestDay(_ date: Date) -> String {
        archiveTestFormatter(format: "yyyy-MM-dd").string(from: date)
    }

    private func archiveTestTimestamp(_ date: Date) -> String {
        archiveTestFormatter(format: "yyyyMMdd-HHmmss").string(from: date)
    }

    private func archiveTestFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}

private final class PathStateLogCollectionFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let pathStates: [String: RuntimePathState]

    init(pathStates: [String: RuntimePathState]) {
        self.pathStates = pathStates
    }

    func fileExists(_ url: URL) -> Bool {
        pathStates[url.path] == .file
    }

    func directoryExists(_ url: URL) -> Bool {
        pathStates[url.path] == .directory
    }

    func pathState(at url: URL) -> RuntimePathState {
        pathStates[url.path] ?? .missing
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

private final class InMemoryLogCollectionFileStore: RuntimeFileStore, RuntimeFilePartialReading {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    var files: [URL: Data]
    var modificationDates: [URL: Date]
    var directories: Set<URL>

    init(
        files: [URL: Data],
        modificationDates: [URL: Date] = [:],
        directories: Set<URL> = []
    ) {
        self.files = files
        self.modificationDates = modificationDates
        self.directories = directories
    }

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        directories.contains(url)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        false
    }

    func pathState(at url: URL) -> RuntimePathState {
        if files[url] != nil {
            return .file
        }
        if directories.contains(url) {
            return .directory
        }
        return .missing
    }

    func readData(_ url: URL) throws -> Data {
        guard let data = files[url] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func readData(_ url: URL, offset: UInt64?) throws -> Data {
        let data = try readData(url)
        guard let offset else {
            return data
        }
        guard offset < UInt64(data.count) else {
            return Data()
        }
        return Data(data.dropFirst(Int(offset)))
    }

    func readUTF8Text(_ url: URL) throws -> String {
        String(decoding: try readData(url), as: UTF8.self)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        UInt64(try readData(url).count)
    }

    func modificationDate(_ url: URL) throws -> Date {
        guard let date = modificationDates[url] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return date
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        files[url] = data
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {
        try writeData(data, to: url, options: options)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        directories.insert(url)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url)
        directories.remove(url)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
        files.removeValue(forKey: source)
    }

    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        files.keys.filter { $0.deletingLastPathComponent() == url }
    }

    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        directories.filter { $0.deletingLastPathComponent() == url && $0.lastPathComponent.contains(fragment) }
    }

    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        files
            .filter { $0.key.path.hasPrefix(url.path) }
            .reduce(UInt64(0)) { total, entry in total + UInt64(entry.value.count) }
    }

    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1_000_000)
    }
}
