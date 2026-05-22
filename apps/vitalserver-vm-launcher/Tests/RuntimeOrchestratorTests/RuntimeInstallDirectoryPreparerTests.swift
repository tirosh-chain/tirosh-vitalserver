import Foundation
import RuntimeInfrastructure
@testable import RuntimeOrchestrator
import XCTest

final class RuntimeInstallDirectoryPreparerTests: XCTestCase {
    func testPrepareCreatesRuntimeDirectoriesAndCustomVitalFilesDirectory() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let preparer = RuntimeInstallDirectoryPreparer(
            installedPaths: paths,
            fileStore: fileStore,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        try preparer.prepare(settings: InstallSettings(vitalFilesDirectory: "/custom/vital-files"))

        XCTAssertTrue(fileStore.directories.contains(paths.runtimeDirectory))
        XCTAssertTrue(fileStore.directories.contains(URL(fileURLWithPath: "/custom/vital-files")))
        XCTAssertTrue(fileStore.directories.contains(paths.deployDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.guestRunDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.vrReleaseDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.productLogsDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.centralRuntimeLogsDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.centralGuestLogsDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.logArchiveDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.hostRunDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.statusDirectory))
        XCTAssertTrue(fileStore.directories.contains(paths.nginxLogsDirectory))
    }

    func testPrepareMigratesLegacyRuntimeLogsToCentralDirectory() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let fileStore = LocalRuntimeFileStore()
        let paths = InstalledRuntimePaths(productRoot: temporaryRoot.appendingPathComponent("product"))
        let legacyLog = paths.logsDirectory.appendingPathComponent("launcher.log")
        let centralLog = paths.centralRuntimeLogsDirectory.appendingPathComponent("launcher.log")
        try fileStore.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        try fileStore.writeData(Data("legacy".utf8), to: legacyLog, options: .atomic)
        let preparer = RuntimeInstallDirectoryPreparer(
            installedPaths: paths,
            fileStore: fileStore,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        try preparer.prepare(settings: InstallSettings(
            vitalFilesDirectory: temporaryRoot.appendingPathComponent("custom/vital-files").path
        ))

        XCTAssertFalse(fileStore.fileExists(legacyLog))
        XCTAssertEqual(try fileStore.readData(centralLog), Data("legacy".utf8))
        XCTAssertFalse(fileStore.directoryExists(paths.logsDirectory))
    }

    func testPreparePreservesExistingCentralLogByUsingTimestampedLegacyName() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        let fileStore = LocalRuntimeFileStore()
        let paths = InstalledRuntimePaths(productRoot: temporaryRoot.appendingPathComponent("product"))
        let legacyLog = paths.logsDirectory.appendingPathComponent("launcher.log")
        let centralLog = paths.centralRuntimeLogsDirectory.appendingPathComponent("launcher.log")
        let migratedLog = paths.centralRuntimeLogsDirectory.appendingPathComponent("legacy-launcher.log.1700000000")
        try fileStore.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        try fileStore.createDirectory(at: paths.centralRuntimeLogsDirectory, withIntermediateDirectories: true)
        try fileStore.writeData(Data("legacy".utf8), to: legacyLog, options: .atomic)
        try fileStore.writeData(Data("central".utf8), to: centralLog, options: .atomic)
        let preparer = RuntimeInstallDirectoryPreparer(
            installedPaths: paths,
            fileStore: fileStore,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        try preparer.prepare(settings: InstallSettings(
            vitalFilesDirectory: temporaryRoot.appendingPathComponent("custom/vital-files").path
        ))

        XCTAssertEqual(try fileStore.readData(centralLog), Data("central".utf8))
        XCTAssertEqual(try fileStore.readData(migratedLog), Data("legacy".utf8))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeInstallDirectoryPreparerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
