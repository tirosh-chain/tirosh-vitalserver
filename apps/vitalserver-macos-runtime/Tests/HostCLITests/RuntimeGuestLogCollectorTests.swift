import Foundation
import HostInfrastructure
@testable import HostCLI
import XCTest

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

        try RuntimeGuestLogCollector(installedPaths: paths, fileStore: fileStore).collect()

        XCTAssertEqual(try String(contentsOf: paths.centralContainerLogs, encoding: .utf8), "new\n")
        let archiveEntries = try fileStore.contentsOfDirectory(
            at: paths.logArchiveDirectory.appendingPathComponent("guest"),
            skipsHiddenFiles: true
        )
        XCTAssertTrue(archiveEntries.contains { $0.lastPathComponent.hasPrefix("container-logs.log.") })
    }
}
