import XCTest
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

        let folders = SystemRuntimeHostFileReader().vitalFileFolders(root: directory.path)

        XCTAssertEqual(folders.map(\.name), ["alpha", "zeta"])
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

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeFileReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class FakeRuntimeLogCollector: RuntimeLogCollecting {
    var refreshCount = 0

    func refreshLogCollection() {
        refreshCount += 1
    }
}
