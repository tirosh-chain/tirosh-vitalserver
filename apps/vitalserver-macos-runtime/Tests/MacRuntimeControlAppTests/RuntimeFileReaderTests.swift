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
