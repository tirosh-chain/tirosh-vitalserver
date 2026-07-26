import XCTest
import Errors
import Application
import Contracts
import Domain
import RuntimeControl
@testable import OutboundAdapters
@testable import MacControlPanelHost
@testable import InboundAdapters

final class RuntimeFileReaderTests: XCTestCase {
    func testUpdateBundleSummaryReadsManifestArtifacts() throws {
        let directory = try temporaryDirectory()
        try """
        {
          "schemaVersion": 2,
          "product": "vitalserver",
          "bundleKind": "product-update",
          "channel": "dev",
          "helperVersion": "1.2.3",
          "releaseLabel": "1.2.3",
          "targetPlatform": "macos-arm64",
          "components": {
            "updater": "1.2.3"
          },
          "createdAt": "2026-05-30T00:00:00Z",
          "artifacts": [
            { "type": "rootfs-base", "name": "rootfs.img.gz", "sha256": "rootfs-digest", "size": 100 },
            { "type": "app-bundle", "name": "vitalserver.tar.gz", "sha256": "app-digest", "size": 200 }
          ],
          "migrations": []
        }
        """.write(
            to: directory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        let summary = displayHostText(SystemRuntimeHostFileReader().updateBundleSummaryResult(url: directory))

        XCTAssertTrue(summary.contains("Version: 1.2.3"))
        XCTAssertTrue(summary.contains("rootfs-base: rootfs.img.gz"))
        XCTAssertTrue(summary.contains("app-bundle: vitalserver.tar.gz"))
    }

    func testUpdateBundleSummaryReportsMissingManifest() throws {
        let directory = try temporaryDirectory()

        XCTAssertEqual(
            SystemRuntimeHostFileReader().updateBundleSummaryResult(url: directory),
            .missing(.message("Missing manifest.json"))
        )
        XCTAssertEqual(
            displayHostText(SystemRuntimeHostFileReader().updateBundleSummaryResult(url: directory)),
            "Missing manifest.json"
        )
    }

    func testUpdateBundleSummaryReportsManifestPathInspectionFailure() {
        let directory = URL(fileURLWithPath: "/bundle")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let reader = SystemRuntimeHostFileReader(
            fileStore: PathStateRuntimeFileStore(pathStates: [
                manifestURL.path: .inspectFailed("permission denied"),
            ])
        )

        XCTAssertEqual(
            reader.updateBundleSummaryResult(url: directory),
            .failed("Manifest path inspection failed: /bundle/manifest.json reason=permission denied")
        )
        XCTAssertEqual(
            displayHostText(reader.updateBundleSummaryResult(url: directory)),
            "Manifest path inspection failed: /bundle/manifest.json reason=permission denied"
        )
    }

    func testUpdateBundleSummaryReportsInvalidManifest() throws {
        let directory = try temporaryDirectory()
        try "{invalid-json".write(
            to: directory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertTrue(
            displayHostText(SystemRuntimeHostFileReader().updateBundleSummaryResult(url: directory))
                .hasPrefix("Invalid manifest.json:")
        )
    }

    func testUpdateBundleSummaryReportsArchiveInput() {
        let archive = URL(fileURLWithPath: "/tmp/update-bundle-1.2.3.tar.gz")

        XCTAssertEqual(
            displayHostText(SystemRuntimeHostFileReader().updateBundleSummaryResult(url: archive)),
            "Archive: update-bundle-1.2.3.tar.gz\nCheck integrity to inspect manifest and checksums. Publisher authenticity is unverified."
        )
    }

    func testVitalFileFoldersReturnsSortedDirectoriesOnly() throws {
        let directory = try temporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("zeta"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("alpha"),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("plain.txt").path,
            contents: Data()
        )

        let folders = try SystemRuntimeHostFileReader().vitalFileFolders(root: directory.path)

        XCTAssertEqual(folders.map(\.name), ["alpha", "zeta"])
    }

    func testVitalFileFoldersPropagatesDirectoryReadFailure() {
        let reader = SystemRuntimeHostFileReader(fileStore: FailingDirectoryRuntimeFileStore())

        XCTAssertThrowsError(try reader.vitalFileFolders(root: "/restricted"))
    }

    func testVitalFileFoldersPropagatesEntryPathInspectionFailure() {
        let root = URL(fileURLWithPath: "/vital-files")
        let unreadable = root.appendingPathComponent("unreadable")
        let reader = SystemRuntimeHostFileReader(
            fileStore: PathStateRuntimeFileStore(
                pathStates: [unreadable.path: .inspectFailed("permission denied")],
                directoryContents: [root.path: [unreadable]]
            )
        )

        XCTAssertThrowsError(try reader.vitalFileFolders(root: root.path)) { error in
            XCTAssertEqual(
                error as? RuntimeHostFileReaderError,
                .pathInspectionFailed(path: unreadable.path, reason: "permission denied")
            )
        }
    }

    func testHelperMessageLogTextReadsPersistedHelperMessageLog() {
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(dataByPath: [
                RuntimeControlClientConstants.Paths.helperMessageLogFile: Data("first\nsecond\nthird".utf8),
            ])
        )

        XCTAssertEqual(
            displayLogText(reader.logTextResult(sourceID: .helperMessage, lineLimit: 2)),
            "second\nthird"
        )
    }

    func testHelperMessageLogTextReportsMissingMessageWhenPersistedLogIsMissing() {
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(existingFiles: [])
        )
        let result = reader.logTextResult(sourceID: .helperMessage, lineLimit: 10)

        XCTAssertEqual(
            result,
            .missing(.message("Log file is missing path=\(RuntimeControlClientConstants.Paths.helperMessageLogFile)"))
        )
        XCTAssertEqual(displayLogText(result), "Log file is missing path=\(RuntimeControlClientConstants.Paths.helperMessageLogFile)")
    }

    func testHelperMessageLogTextReportsPathInspectionFailure() {
        let reader = SystemRuntimeHostFileReader(
            fileStore: PathStateRuntimeFileStore(pathStates: [
                RuntimeControlClientConstants.Paths.helperMessageLogFile: .inspectFailed("permission denied"),
            ])
        )

        XCTAssertEqual(
            reader.logTextResult(sourceID: .helperMessage, lineLimit: 10),
            .failed(
                "Log file path inspection failed " +
                    "\(RuntimeControlClientConstants.Paths.helperMessageLogFile): permission denied"
            )
        )
        XCTAssertEqual(
            displayLogText(reader.logTextResult(sourceID: .helperMessage, lineLimit: 10)),
            "Log file path inspection failed \(RuntimeControlClientConstants.Paths.helperMessageLogFile): permission denied"
        )
    }

    func testNonContainerFileLogTextRefreshesLogCollectionBeforeReading() throws {
        let collector = FakeRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(logCollector: collector)

        _ = reader.logTextResult(sourceID: .launcher, lineLimit: 10)

        XCTAssertEqual(collector.refreshCount, 1)
    }

    func testLogTextReportsLogCollectionRefreshFailure() throws {
        let collector = FakeRuntimeLogCollector(refreshError: CocoaError(.fileReadNoPermission))
        let reader = SystemRuntimeHostFileReader(logCollector: collector)
        let displayCollector = FakeRuntimeLogCollector(refreshError: CocoaError(.fileReadNoPermission))
        let displayReader = SystemRuntimeHostFileReader(logCollector: displayCollector)

        let logResult = reader.logTextResult(sourceID: .launcher, lineLimit: 10)
        let logText = displayLogText(displayReader.logTextResult(sourceID: .launcher, lineLimit: 10))

        guard case .failed(let message) = logResult else {
            XCTFail("Expected failed log result, got \(logResult)")
            return
        }
        XCTAssertTrue(message.hasPrefix("Failed to refresh log collection:"))
        XCTAssertTrue(logText.hasPrefix("Failed to refresh log collection:"))
        XCTAssertEqual(collector.refreshCount, 1)
        XCTAssertEqual(displayCollector.refreshCount, 1)
    }

    func testLogTextPreservesRefreshFailureWhenExistingCollectedLogCanBeRead() throws {
        let source = RuntimeLogSourceReadStrategyCatalog().strategy(for: .launcher).fileSource
        let collector = FakeRuntimeLogCollector(refreshError: CocoaError(.fileReadNoPermission))
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(dataByPath: [
                source.path: Data("first\nsecond\nthird".utf8),
            ]),
            logCollector: collector
        )

        let result = reader.logTextResult(sourceID: .launcher, lineLimit: 2)

        guard case .loadedWithIssue(let text, let issue) = result else {
            XCTFail("Expected loaded log text with refresh issue, got \(result)")
            return
        }
        XCTAssertEqual(text, "second\nthird")
        XCTAssertTrue(issue.hasPrefix("Failed to refresh log collection:"))
        XCTAssertTrue(displayLogText(result).contains(issue))
        XCTAssertTrue(displayLogText(result).contains(text))
        XCTAssertEqual(collector.sourceIDs, [.launcher])
        XCTAssertEqual(collector.refreshCount, 1)
    }

    func testLogTextPreservesRefreshFailureWhenLogReadAlsoFails() throws {
        let source = RuntimeLogSourceReadStrategyCatalog().strategy(for: .launcher).fileSource
        let collector = FakeRuntimeLogCollector(refreshError: CocoaError(.fileReadNoPermission))
        let reader = SystemRuntimeHostFileReader(
            fileStore: PathStateRuntimeFileStore(pathStates: [
                source.path: .inspectFailed("acl denied"),
            ]),
            logCollector: collector
        )

        let result = reader.logTextResult(sourceID: .launcher, lineLimit: 2)

        guard case .failed(let message) = result else {
            XCTFail("Expected failed log text with refresh and read issues, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("Failed to refresh log collection:"))
        XCTAssertTrue(message.contains("Log file path inspection failed"))
        XCTAssertTrue(message.contains("acl denied"))
        XCTAssertEqual(collector.sourceIDs, [.launcher])
        XCTAssertEqual(collector.refreshCount, 1)
    }

    func testCommandLogTextReadsSourceWithoutRefreshingLogCollection() throws {
        let collector = FakeRuntimeLogCollector(refreshError: CocoaError(.fileReadNoPermission))
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(dataByPath: [
                RuntimeControlClientConstants.Paths.commandLogFile: Data("first\nsecond\nthird".utf8),
            ]),
            logCollector: collector
        )

        let logText = displayLogText(reader.logTextResult(sourceID: .command, lineLimit: 2))

        XCTAssertEqual(logText, "second\nthird")
        XCTAssertEqual(collector.sourceIDs, [])
        XCTAssertEqual(collector.refreshCount, 0)
    }

    func testLogTextReportsLogFileReadFailure() throws {
        let fileStore = ExistingLogRuntimeFileStore()
        let reader = SystemRuntimeHostFileReader(fileStore: fileStore)

        let logText = displayLogText(reader.logTextResult(sourceID: .install, lineLimit: 10))

        XCTAssertTrue(logText.hasPrefix("Failed to read log file "))
        XCTAssertTrue(logText.contains(RuntimeControlClientConstants.Paths.installLog))
    }

    func testLogTextReportsInvalidUTF8LogFile() throws {
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(dataByPath: [
                RuntimeControlClientConstants.Paths.installLog: Data([0xff]),
            ]),
            logCollector: FakeRuntimeLogCollector()
        )

        let logText = displayLogText(reader.logTextResult(sourceID: .install, lineLimit: 10))

        XCTAssertTrue(logText.hasPrefix("Failed to read log file "))
        XCTAssertTrue(logText.contains(RuntimeControlClientConstants.Paths.installLog))
        XCTAssertFalse(logText.contains(AppConstants.StatusText.noLogData))
    }

    func testCommandLogTextReadsFallbackSourceAndTailsLargeFile() throws {
        let padding = String(repeating: "x", count: 130 * 1024)
        let logData = Data("\(padding)\nfirst\nsecond\nthird".utf8)
        let collector = FakeRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(dataByPath: [
                RuntimeControlClientConstants.Paths.commandLogFile: logData,
            ]),
            logCollector: collector
        )

        let logText = displayLogText(reader.logTextResult(sourceID: .command, lineLimit: 2))

        XCTAssertEqual(logText, "second\nthird")
        XCTAssertEqual(collector.sourceIDs, [])
        XCTAssertEqual(collector.refreshCount, 0)
    }

    func testLogTextCoversDiagnosticLogSourcesWhenFilesAreMissing() {
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(existingFiles: []),
            logCollector: FakeRuntimeLogCollector()
        )

        for sourceID in [
            RuntimeLogSource.vmLaunchOutput,
            .vmLaunchError,
            .proxyOutput,
            .proxyError,
            .watchdog,
            .updateActivation,
            .updateShutdown,
        ] {
            let result = reader.logTextResult(sourceID: sourceID, lineLimit: 10)
            guard case .missing(.message(let message)) = result else {
                return XCTFail("Expected missing log file message for \(sourceID.rawValue), got \(result)")
            }
            XCTAssertTrue(message.contains("Log files are missing primary="), "Expected primary path in \(message)")
            XCTAssertTrue(message.contains(" source="), "Expected source path in \(message)")
            XCTAssertEqual(displayLogText(result), message)
        }
    }

    func testContainerLogTextRefreshesOnlyWhenCentralLogIsMissing() {
        let missingCollector = FakeRuntimeLogCollector()
        let missingReader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(existingFiles: []),
            logCollector: missingCollector
        )

        XCTAssertEqual(
            missingReader.logTextResult(sourceID: .containers, lineLimit: 10),
            .missing(
                .message(
                    "Log files are missing primary=\(RuntimeControlClientConstants.Paths.containerLogs) " +
                        "source=\(RuntimeControlClientConstants.Paths.containerLogSource)"
                )
            )
        )
        XCTAssertEqual(missingCollector.sourceIDs, [.containers])

        let existingCollector = FakeRuntimeLogCollector()
        let existingReader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(existingFiles: [RuntimeControlClientConstants.Paths.containerLogs]),
            logCollector: existingCollector
        )

        XCTAssertEqual(
            existingReader.logTextResult(sourceID: .containers, lineLimit: 10),
            .missing(.noData)
        )
        XCTAssertEqual(existingCollector.refreshCount, 0)
    }

    func testHelperMessageLogTextDoesNotRefreshLogCollection() throws {
        let collector = FakeRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(logCollector: collector)

        _ = reader.logTextResult(sourceID: .helperMessage, lineLimit: 10)

        XCTAssertEqual(collector.refreshCount, 0)
    }

    func testPreferredLogsPathReturnsProductLogsDirectory() {
        XCTAssertEqual(
            SystemRuntimeHostFileReader().preferredLogsPath(),
            RuntimeControlClientConstants.Paths.productLogs
        )
    }

    func testBackupReaderWrappersPropagateReadFailures() {
        let reader = SystemRuntimeHostFileReader(fileStore: BackupSizeFailingRuntimeFileStore())

        XCTAssertThrowsError(try reader.backups(latestBackupPath: "/backups/latest-before-version"))
        XCTAssertThrowsError(try reader.redisBackups())
    }

    func testBackupListPropagatesDirectoryReadFailure() {
        let fileStore = FailingDirectoryRuntimeFileStore()

        XCTAssertThrowsError(try RuntimeBackup.loadAll(fileStore: fileStore))
    }

    func testRedisBackupListPropagatesDirectoryReadFailure() {
        let fileStore = FailingDirectoryRuntimeFileStore()

        XCTAssertThrowsError(try RuntimeBackup.loadRedisBackups(fileStore: fileStore))
    }

    func testRuntimeDataBackupListReportsMissingManagedDirectoryDistinctFromEmpty() throws {
        let fileStore = PathStateRuntimeFileStore(pathStates: [
            RuntimeControlClientConstants.Paths.runtimeDataBackups: .missing,
        ])

        XCTAssertThrowsError(try RuntimeBackup.loadRuntimeDataBackups(fileStore: fileStore)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupListError,
                .unexpectedPathState(path: RuntimeControlClientConstants.Paths.runtimeDataBackups, state: "missing")
            )
        }
    }

    func testRuntimeDataBackupListIncludesAutomaticBackupDirectories() throws {
        let directory = RuntimeControlClientConstants.Paths.runtimeDataBackups
        let automatic = URL(fileURLWithPath: directory)
            .appendingPathComponent("20260614T181517Z-automatic")
        let manual = URL(fileURLWithPath: directory)
            .appendingPathComponent("20260614T140508Z-manual")
        let fileStore = PathStateRuntimeFileStore(
            pathStates: [
                directory: .directory,
                automatic.path: .directory,
                manual.path: .directory,
            ],
            directoryContents: [
                directory: [manual, automatic],
            ]
        )

        let backups = try RuntimeBackup.loadRuntimeDataBackups(fileStore: fileStore)

        XCTAssertEqual(backups.map(\.path), [automatic.path, manual.path])
    }

    func testRuntimeDataBackupListReportsManagedDirectoryInspectionFailure() {
        let fileStore = PathStateRuntimeFileStore(pathStates: [
            RuntimeControlClientConstants.Paths.runtimeDataBackups: .inspectFailed("permission denied"),
        ])

        XCTAssertThrowsError(try RuntimeBackup.loadRuntimeDataBackups(fileStore: fileStore)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupListError,
                .pathInspectionFailed(
                    path: RuntimeControlClientConstants.Paths.runtimeDataBackups,
                    reason: "permission denied"
                )
            )
        }
    }

    func testRuntimeDataBackupListReportsUnexpectedManagedDirectoryState() {
        let fileStore = PathStateRuntimeFileStore(pathStates: [
            RuntimeControlClientConstants.Paths.runtimeDataBackups: .file,
        ])

        XCTAssertThrowsError(try RuntimeBackup.loadRuntimeDataBackups(fileStore: fileStore)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupListError,
                .unexpectedPathState(path: RuntimeControlClientConstants.Paths.runtimeDataBackups, state: "file")
            )
        }
    }

    func testRuntimeDataBackupListReportsChildInspectionFailure() {
        let directory = RuntimeControlClientConstants.Paths.runtimeDataBackups
        let child = URL(fileURLWithPath: directory).appendingPathComponent("20260611T000000Z-manual")
        let fileStore = PathStateRuntimeFileStore(
            pathStates: [
                directory: .directory,
                child.path: .inspectFailed("permission denied"),
            ],
            directoryContents: [
                directory: [child],
            ]
        )

        XCTAssertThrowsError(try RuntimeBackup.loadRuntimeDataBackups(fileStore: fileStore)) { error in
            XCTAssertEqual(
                error as? RuntimeBackupListError,
                .pathInspectionFailed(path: child.path, reason: "permission denied")
            )
        }
    }

    func testBackupListPropagatesSizeReadFailure() {
        let fileStore = BackupSizeFailingRuntimeFileStore()

        XCTAssertThrowsError(try RuntimeBackup.loadAll(fileStore: fileStore))
    }

    func testBackupListReportsInvalidLatestBackupPathDistinctFromMissingLatestBackup() {
        XCTAssertThrowsError(try RuntimeBackup.loadAll(
            latestBackupPath: "/backups/latest",
            fileStore: SpecificFileRuntimeFileStore(existingFiles: [])
        )) { error in
            XCTAssertEqual(error as? RuntimeBackupListError, .invalidLatestBackupPath("/backups/latest"))
        }
    }

    func testBackupListRejectsLatestBackupOutsideManagedBackupRootBeforeSizeRead() {
        let path = "/tmp/20260522T000000Z-before-0.1.3"

        XCTAssertThrowsError(try RuntimeBackup.loadAll(
            latestBackupPath: path,
            fileStore: SpecificFileRuntimeFileStore(existingFiles: [])
        )) { error in
            XCTAssertEqual(error as? RuntimeBackupListError, .invalidLatestBackupPath(path))
        }
    }

    func testRedisBackupListPropagatesSizeReadFailure() {
        let fileStore = BackupSizeFailingRuntimeFileStore()

        XCTAssertThrowsError(try RuntimeBackup.loadRedisBackups(fileStore: fileStore))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeFileReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private func displayLogText(_ result: RuntimeHostTextReadResult) -> String {
    RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.noLogData)
        .displayText(result)
}

private func displayHostText(_ result: RuntimeHostTextReadResult) -> String {
    RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.notReported)
        .displayText(result)
}

private extension RuntimeLogSourceReadStrategy {
    var fileSource: RuntimeLogFileSource {
        switch self {
        case .direct(let source), .refreshThenRead(let source), .refreshWhenPrimaryMissing(let source):
            return source
        }
    }
}

private final class FakeRuntimeLogCollector: RuntimeLogCollecting, @unchecked Sendable {
    var refreshCount = 0
    var sourceIDs: [RuntimeLogSource] = []
    private let refreshError: Error?

    init(refreshError: Error? = nil) {
        self.refreshError = refreshError
    }

    func refreshLogCollection() throws {
        refreshCount += 1
        if let refreshError {
            throw refreshError
        }
    }

    func refreshLogCollection(sourceID: RuntimeLogSource) throws {
        sourceIDs.append(sourceID)
        try refreshLogCollection()
    }
}

private final class SpecificFileRuntimeFileStore: RuntimeFileStore, RuntimeFilePartialReading {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let dataByPath: [String: Data]

    init(existingFiles: Set<String>) {
        self.dataByPath = Dictionary(uniqueKeysWithValues: existingFiles.map { ($0, Data()) })
    }

    init(dataByPath: [String: Data]) {
        self.dataByPath = dataByPath
    }

    func fileExists(_ url: URL) -> Bool { dataByPath.keys.contains(url.path) }
    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func readData(_ url: URL) throws -> Data {
        guard let data = dataByPath[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }
    func readData(_ url: URL, offset: UInt64?) throws -> Data {
        let data = try readData(url)
        guard let offset else {
            return data
        }
        return data.suffix(from: min(Int(offset), data.count))
    }
    func readUTF8Text(_ url: URL) throws -> String { String(decoding: try readData(url), as: UTF8.self) }
    func fileSize(_ url: URL) throws -> UInt64 {
        UInt64(try readData(url).count)
    }
    func modificationDate(_ url: URL) throws -> Date { Date(timeIntervalSince1970: 0) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}

private final class FailingDirectoryRuntimeFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")

    func fileExists(_ url: URL) -> Bool { false }
    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoPermission) }
    func readUTF8Text(_ url: URL) throws -> String { throw CocoaError(.fileReadNoPermission) }
    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoPermission) }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoPermission) }
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

private final class PathStateRuntimeFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let pathStates: [String: RuntimePathState]
    private let directoryContents: [String: [URL]]

    init(
        pathStates: [String: RuntimePathState],
        directoryContents: [String: [URL]] = [:]
    ) {
        self.pathStates = pathStates
        self.directoryContents = directoryContents
    }

    func fileExists(_ url: URL) -> Bool { pathState(at: url) == .file }
    func directoryExists(_ url: URL) -> Bool { pathState(at: url) == .directory }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func fileState(atPath path: String) -> RuntimeFileState { fileState(at: URL(fileURLWithPath: path)) }
    func fileState(at url: URL) -> RuntimeFileState {
        switch pathState(at: url) {
        case .file, .directory, .other:
            .present
        case .missing:
            .missing
        case .inspectFailed(let reason):
            .inspectFailed(reason)
        case .unknown(let value):
            .unknown(value)
        }
    }
    func pathState(at url: URL) -> RuntimePathState { pathStates[url.path] ?? .missing }
    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoSuchFile) }
    func readUTF8Text(_ url: URL) throws -> String { String(decoding: try readData(url), as: UTF8.self) }
    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoSuchFile) }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoSuchFile) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        guard let contents = directoryContents[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return contents
    }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}

private final class BackupSizeFailingRuntimeFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")

    private let backupDirectory = URL(fileURLWithPath: RuntimeControlClientConstants.Paths.backups)
        .appendingPathComponent("20260530T000000Z-before-0.1.9")
    private let redisBackup = URL(fileURLWithPath: RuntimeControlClientConstants.Paths.redisBackups)
        .appendingPathComponent("redis-20260530T000000Z.tar.gz")

    func fileExists(_ url: URL) -> Bool { true }
    func directoryExists(_ url: URL) -> Bool { true }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func readData(_ url: URL) throws -> Data { Data() }
    func readUTF8Text(_ url: URL) throws -> String { "" }
    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoPermission) }
    func modificationDate(_ url: URL) throws -> Date { Date(timeIntervalSince1970: 0) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        [redisBackup]
    }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        [backupDirectory]
    }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        throw CocoaError(.fileReadNoPermission)
    }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}

private final class ExistingLogRuntimeFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")

    func fileExists(_ url: URL) -> Bool { true }
    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func readData(_ url: URL) throws -> Data { throw CocoaError(.fileReadNoPermission) }
    func readUTF8Text(_ url: URL) throws -> String { throw CocoaError(.fileReadNoPermission) }
    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoPermission) }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoPermission) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}
