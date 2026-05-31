import XCTest
import Core
import RuntimeControl
@testable import MacHostRuntimeAdapter
@testable import MacRuntimeControlApp

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

        let summary = SystemRuntimeHostFileReader().updateBundleSummary(url: directory)

        XCTAssertTrue(summary.contains("Version: 1.2.3"))
        XCTAssertTrue(summary.contains("rootfs-base: rootfs.img.gz"))
        XCTAssertTrue(summary.contains("app-bundle: vitalserver.tar.gz"))
    }

    func testUpdateBundleSummaryReportsMissingManifest() throws {
        let directory = try temporaryDirectory()

        XCTAssertEqual(
            SystemRuntimeHostFileReader().updateBundleSummary(url: directory),
            "Missing manifest.json"
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
            SystemRuntimeHostFileReader().updateBundleSummary(url: directory)
                .hasPrefix("Invalid manifest.json:")
        )
    }

    func testUpdateBundleSummaryReportsArchiveInput() {
        let archive = URL(fileURLWithPath: "/tmp/update-bundle-1.2.3.tar.gz")

        XCTAssertEqual(
            SystemRuntimeHostFileReader().updateBundleSummary(url: archive),
            "Archive: update-bundle-1.2.3.tar.gz\nVerify to inspect manifest and checksums."
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

    func testHelperMessageLogTextReadsPersistedHelperMessageLog() {
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(dataByPath: [
                RuntimeAdapterConstants.Paths.helperMessageLogFile: Data("first\nsecond\nthird".utf8),
            ])
        )

        XCTAssertEqual(
            reader.logText(sourceID: .helperMessage, helperMessage: "ignored", lineLimit: 2),
            "second\nthird"
        )
    }

    func testHelperMessageLogTextReportsNoDataWhenPersistedLogIsMissing() {
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(existingFiles: [])
        )

        XCTAssertEqual(
            reader.logText(sourceID: .helperMessage, helperMessage: "Ready", lineLimit: 10),
            AppConstants.StatusText.noLogData
        )
    }

    func testNonContainerFileLogTextRefreshesLogCollectionBeforeReading() throws {
        let collector = FakeRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(logCollector: collector)

        _ = reader.logText(sourceID: .launcher, helperMessage: "Ready", lineLimit: 10)

        XCTAssertEqual(collector.refreshCount, 1)
    }

    func testLogTextReportsLogCollectionRefreshFailure() throws {
        let collector = FakeRuntimeLogCollector(refreshError: CocoaError(.fileReadNoPermission))
        let reader = SystemRuntimeHostFileReader(logCollector: collector)

        let logText = reader.logText(sourceID: .launcher, helperMessage: "Ready", lineLimit: 10)

        XCTAssertTrue(logText.hasPrefix("Failed to refresh log collection:"))
        XCTAssertEqual(collector.refreshCount, 1)
    }

    func testLogTextReadsAvailableSourceWhenRefreshFails() throws {
        let collector = FakeRuntimeLogCollector(refreshError: CocoaError(.fileReadNoPermission))
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(dataByPath: [
                RuntimeAdapterConstants.Paths.commandLogFile: Data("first\nsecond\nthird".utf8),
            ]),
            logCollector: collector
        )

        let logText = reader.logText(sourceID: .command, helperMessage: "Ready", lineLimit: 2)

        XCTAssertEqual(logText, "second\nthird")
        XCTAssertEqual(collector.sourceIDs, [.command])
    }

    func testLogTextReportsLogFileReadFailure() throws {
        let fileStore = ExistingLogRuntimeFileStore()
        let reader = SystemRuntimeHostFileReader(fileStore: fileStore)

        let logText = reader.logText(sourceID: .install, helperMessage: "Ready", lineLimit: 10)

        XCTAssertTrue(logText.hasPrefix("Failed to read log file "))
        XCTAssertTrue(logText.contains(RuntimeAdapterConstants.Paths.installLog))
    }

    func testCommandLogTextReadsFallbackSourceAndTailsLargeFile() throws {
        let padding = String(repeating: "x", count: 130 * 1024)
        let logData = Data("\(padding)\nfirst\nsecond\nthird".utf8)
        let collector = FakeRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(dataByPath: [
                RuntimeAdapterConstants.Paths.commandLogFile: logData,
            ]),
            logCollector: collector
        )

        let logText = reader.logText(sourceID: .command, helperMessage: "Ready", lineLimit: 2)

        XCTAssertEqual(logText, "second\nthird")
        XCTAssertEqual(collector.sourceIDs, [.command])
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
            XCTAssertEqual(
                reader.logText(sourceID: sourceID, helperMessage: "Ready", lineLimit: 10),
                RuntimeAdapterConstants.StatusText.noLogData,
                "Expected no data for \(sourceID.rawValue)"
            )
        }
    }

    func testContainerLogTextRefreshesOnlyWhenCentralLogIsMissing() {
        let missingCollector = FakeRuntimeLogCollector()
        let missingReader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(existingFiles: []),
            logCollector: missingCollector
        )

        XCTAssertEqual(
            missingReader.logText(sourceID: .containers, helperMessage: "Ready", lineLimit: 10),
            RuntimeAdapterConstants.StatusText.noLogData
        )
        XCTAssertEqual(missingCollector.sourceIDs, [.containers])

        let existingCollector = FakeRuntimeLogCollector()
        let existingReader = SystemRuntimeHostFileReader(
            fileStore: SpecificFileRuntimeFileStore(existingFiles: [RuntimeAdapterConstants.Paths.containerLogs]),
            logCollector: existingCollector
        )

        XCTAssertEqual(
            existingReader.logText(sourceID: .containers, helperMessage: "Ready", lineLimit: 10),
            RuntimeAdapterConstants.StatusText.noLogData
        )
        XCTAssertEqual(existingCollector.refreshCount, 0)
    }

    func testHelperMessageLogTextDoesNotRefreshLogCollection() throws {
        let collector = FakeRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(logCollector: collector)

        _ = reader.logText(sourceID: .helperMessage, helperMessage: "Ready", lineLimit: 10)

        XCTAssertEqual(collector.refreshCount, 0)
    }

    func testPreferredLogsPathReturnsProductLogsDirectory() {
        XCTAssertEqual(
            SystemRuntimeHostFileReader().preferredLogsPath(),
            RuntimeAdapterConstants.Paths.productLogs
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

    func testBackupListPropagatesSizeReadFailure() {
        let fileStore = BackupSizeFailingRuntimeFileStore()

        XCTAssertThrowsError(try RuntimeBackup.loadAll(fileStore: fileStore))
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

private final class BackupSizeFailingRuntimeFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")

    private let backupDirectory = URL(fileURLWithPath: RuntimeAdapterConstants.Paths.backups)
        .appendingPathComponent("20260530T000000Z-before-0.1.9")
    private let redisBackup = URL(fileURLWithPath: RuntimeAdapterConstants.Paths.redisBackups)
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
