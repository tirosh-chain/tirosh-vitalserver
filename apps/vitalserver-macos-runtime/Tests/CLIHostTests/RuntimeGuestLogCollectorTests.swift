import Foundation
import Application
import Contracts
import Domain
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeGuestLogCollectorTests: XCTestCase {
    func testCollectCopiesAndAppendsGuestContainerLogsToCentralGuestLogs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeGuestLogCollectorTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = InstalledRuntimePaths(productRoot: root)
        let fileStore = SystemRuntimeFileStore()
        try fileStore.createDirectory(at: paths.guestRunDirectory, withIntermediateDirectories: true)
        try Data("first\n".utf8).write(to: paths.containerLogs)

        let collector = RuntimeGuestLogCollector(installedPaths: paths, fileStore: fileStore)
        try collector.collect()

        XCTAssertEqual(try String(contentsOf: paths.centralContainerLogs, encoding: .utf8), "first\n")

        let handle = try FileHandle(forWritingTo: paths.containerLogs)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("second\n".utf8))
        try handle.close()

        try collector.collect()

        XCTAssertEqual(try String(contentsOf: paths.centralContainerLogs, encoding: .utf8), "first\nsecond\n")
    }

    func testCollectCopiesRotatedContainerLogsAndGuestOperationLogs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeGuestLogCollectorTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = InstalledRuntimePaths(productRoot: root)
        let fileStore = SystemRuntimeFileStore()
        try fileStore.createDirectory(at: paths.guestRunDirectory, withIntermediateDirectories: true)
        try Data("rotated\n".utf8).write(to: paths.guestRunDirectory.appendingPathComponent("container-logs.log.1"))
        try Data("redis\n".utf8).write(to: paths.redisBackupLog)
        try Data("shutdown\n".utf8).write(to: paths.updateShutdownLog)

        try RuntimeGuestLogCollector(installedPaths: paths, fileStore: fileStore).collect()

        XCTAssertEqual(
            try String(
                contentsOf: paths.centralGuestLogsDirectory.appendingPathComponent("container-logs.log.1"),
                encoding: .utf8
            ),
            "rotated\n"
        )
        XCTAssertEqual(try String(contentsOf: paths.centralRedisBackupLog, encoding: .utf8), "redis\n")
        XCTAssertEqual(try String(contentsOf: paths.centralUpdateShutdownLog, encoding: .utf8), "shutdown\n")
    }

    func testCollectArchivesCentralLogWhenSourceWasRotatedOrRecreated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeGuestLogCollectorTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = InstalledRuntimePaths(productRoot: root)
        let fileStore = SystemRuntimeFileStore()
        try fileStore.createDirectory(at: paths.guestRunDirectory, withIntermediateDirectories: true)
        try fileStore.createDirectory(at: paths.centralGuestLogsDirectory, withIntermediateDirectories: true)
        try Data("new\n".utf8).write(to: paths.containerLogs)
        try Data("old\nlonger\n".utf8).write(to: paths.centralContainerLogs)

        try RuntimeGuestLogCollector(
            installedPaths: paths,
            fileStore: fileStore,
            archiveTimestamp: { "20260608-120000" }
        ).collect()

        XCTAssertEqual(try String(contentsOf: paths.centralContainerLogs, encoding: .utf8), "new\n")
        let archiveEntries = try fileStore.contentsOfDirectory(
            at: paths.logArchiveDirectory.appendingPathComponent("guest"),
            skipsHiddenFiles: true
        )
        XCTAssertTrue(archiveEntries.contains { $0.lastPathComponent == "container-logs.log.20260608-120000" })
    }

    func testCollectUsesExplicitArchiveCollisionIDWhenTimestampCandidatesAreExhausted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeGuestLogCollectorTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = InstalledRuntimePaths(productRoot: root)
        let fileStore = SystemRuntimeFileStore()
        let archiveDirectory = paths.logArchiveDirectory.appendingPathComponent("guest")
        let archiveBase = archiveDirectory.appendingPathComponent("container-logs.log.20260608-120000")
        try fileStore.createDirectory(at: paths.guestRunDirectory, withIntermediateDirectories: true)
        try fileStore.createDirectory(at: paths.centralGuestLogsDirectory, withIntermediateDirectories: true)
        try fileStore.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        try Data("new\n".utf8).write(to: paths.containerLogs)
        try Data("old\nlonger\n".utf8).write(to: paths.centralContainerLogs)
        try Data("collision\n".utf8).write(to: archiveBase)
        for index in 1...999 {
            try Data("collision \(index)\n".utf8)
                .write(to: archiveDirectory.appendingPathComponent("container-logs.log.20260608-120000.\(index)"))
        }

        try RuntimeGuestLogCollector(
            installedPaths: paths,
            fileStore: fileStore,
            archiveTimestamp: { "20260608-120000" },
            archiveCollisionID: { "collision-id" }
        ).collect()

        XCTAssertEqual(try String(contentsOf: paths.centralContainerLogs, encoding: .utf8), "new\n")
        XCTAssertEqual(
            try String(
                contentsOf: archiveDirectory.appendingPathComponent("container-logs.log.20260608-120000.collision-id"),
                encoding: .utf8
            ),
            "old\nlonger\n"
        )
    }

    func testCollectPropagatesRotatedLogDirectoryReadFailure() {
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = FailingGuestLogDirectoryFileStore(guestRunDirectory: paths.guestRunDirectory)

        XCTAssertThrowsError(try RuntimeGuestLogCollector(installedPaths: paths, fileStore: fileStore).collect())
    }

    func testCollectFailsWhenGuestLogSourceInspectionFails() {
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates[paths.containerLogs.path] = .inspectFailed("permission denied")

        XCTAssertThrowsError(try RuntimeGuestLogCollector(installedPaths: paths, fileStore: fileStore).collect()) { error in
            XCTAssertEqual(
                error as? RuntimeGuestLogCollectorError,
                .pathInspectionFailed(path: paths.containerLogs.path, reason: "permission denied")
            )
        }
    }

    func testCollectFailsWhenCentralLogDestinationIsDirectory() {
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[paths.containerLogs] = Data("container\n".utf8)
        fileStore.pathStates[paths.centralContainerLogs.path] = .directory

        XCTAssertThrowsError(try RuntimeGuestLogCollector(installedPaths: paths, fileStore: fileStore).collect()) { error in
            XCTAssertEqual(
                error as? RuntimeGuestLogCollectorError,
                .unexpectedPathState(path: paths.centralContainerLogs.path, state: "directory")
            )
        }
    }

    func testCollectFailsWhenGuestRunDirectoryInspectionFails() {
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates[paths.guestRunDirectory.path] = .inspectFailed("permission denied")

        XCTAssertThrowsError(try RuntimeGuestLogCollector(installedPaths: paths, fileStore: fileStore).collect()) { error in
            XCTAssertEqual(
                error as? RuntimeGuestLogCollectorError,
                .pathInspectionFailed(path: paths.guestRunDirectory.path, reason: "permission denied")
            )
        }
    }
}

private final class FailingGuestLogDirectoryFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let guestRunDirectory: URL

    init(guestRunDirectory: URL) {
        self.guestRunDirectory = guestRunDirectory
    }

    func fileExists(_ url: URL) -> Bool {
        false
    }

    func directoryExists(_ url: URL) -> Bool {
        url == guestRunDirectory
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
