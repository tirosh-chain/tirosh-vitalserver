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
          "version": "1.2.3",
          "artifacts": [
            { "type": "rootfs", "name": "rootfs.img.gz" },
            { "type": "package", "name": "vitalserver.tar.gz" }
          ]
        }
        """.write(
            to: directory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        let summary = SystemRuntimeHostFileReader().updateBundleSummary(url: directory)

        XCTAssertTrue(summary.contains("Version: 1.2.3"))
        XCTAssertTrue(summary.contains("rootfs: rootfs.img.gz"))
        XCTAssertTrue(summary.contains("package: vitalserver.tar.gz"))
    }

    func testUpdateBundleSummaryReportsInvalidManifest() throws {
        let directory = try temporaryDirectory()

        XCTAssertEqual(
            SystemRuntimeHostFileReader().updateBundleSummary(url: directory),
            "Missing or invalid manifest.json"
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

    func testHelperMessageLogTextUsesNoDataForBlankMessage() {
        let reader = SystemRuntimeHostFileReader()

        XCTAssertEqual(
            reader.logText(sourceID: .helperMessage, helperMessage: "  \n", lineLimit: 10),
            AppConstants.StatusText.noLogData
        )
        XCTAssertEqual(
            reader.logText(sourceID: .helperMessage, helperMessage: "Ready", lineLimit: 10),
            "Ready"
        )
    }

    func testNonContainerFileLogTextRefreshesLogCollectionBeforeReading() throws {
        let collector = FakeRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(logCollector: collector)

        _ = reader.logText(sourceID: .launcher, helperMessage: "Ready", lineLimit: 10)

        XCTAssertEqual(collector.refreshCount, 1)
    }

    func testHelperMessageLogTextDoesNotRefreshLogCollection() throws {
        let collector = FakeRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(logCollector: collector)

        _ = reader.logText(sourceID: .helperMessage, helperMessage: "Ready", lineLimit: 10)

        XCTAssertEqual(collector.refreshCount, 0)
    }

    func testBackupListPropagatesDirectoryReadFailure() {
        let fileStore = FailingDirectoryRuntimeFileStore()

        XCTAssertThrowsError(try RuntimeBackup.loadAll(fileStore: fileStore))
    }

    func testRedisBackupListPropagatesDirectoryReadFailure() {
        let fileStore = FailingDirectoryRuntimeFileStore()

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

    func refreshLogCollection() {
        refreshCount += 1
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
