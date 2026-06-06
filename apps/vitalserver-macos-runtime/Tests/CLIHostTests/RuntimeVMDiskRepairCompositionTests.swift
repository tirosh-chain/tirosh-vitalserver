import Contracts
import Application
import Domain
import Foundation
import Bootstrap
import OutboundAdapters
import XCTest
import Errors

final class RuntimeVMDiskRepairCompositionTests: XCTestCase {
    func testRepairArchivesCurrentDiskAndCreatesReplacementBeforeRestart() throws {
        let harness = try VMDiskRepairHarness()
        try harness.write(harness.rootfsBase, bytes: 2)
        try harness.write(harness.vmDisk, bytes: harness.bytesPerGiB * 40)

        try harness.composition.repair()

        let archivedDisk = try XCTUnwrap(harness.archivedDisk)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedDisk.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.vmDisk.path))
        XCTAssertEqual(try harness.fileSize(harness.vmDisk), harness.bytesPerGiB * 40)
        XCTAssertEqual(harness.events, [
            "log:vm disk repair requested",
            "status:recovering:repair-vm-disk:VM disk repair requested",
            "status:recovering:repair-vm-disk:Creating Redis backup before VM disk repair",
            "redis-backup",
            "log:redis backup before vm disk repair completed",
            "status:recovering:repair-vm-disk:Redis backup completed before VM disk repair",
            "mkdir:runtime:true",
            "mkdir:backups:true",
            "space:runtime:4294967308:repair-vm-disk",
            "status:recovering:repair-vm-disk:Creating replacement VM disk",
            "gunzip:-c rootfs-base.raw.gz:.vm-disk.img.repair.tmp",
            "truncate:-s 40G \(harness.vmDisk.deletingLastPathComponent().appendingPathComponent(".vm-disk.img.repair.tmp").path)",
            "status:recovering:repair-vm-disk:Archiving current VM disk",
            "stop-for-disk-replacement",
            "mkdir:vm-disk-repair-20260529T081838Z:true",
            "move:vm-disk.img:vm-disk.img",
            "log:archived vm disk path=\(archivedDisk.path)",
            "move:.vm-disk.img.repair.tmp:vm-disk.img",
            "log:created replacement vm disk path=\(harness.vmDisk.path) size=40 GiB",
            "status:recovering:repair-vm-disk:Starting runtime services after VM disk repair",
            "start:true:true:true",
            "wait:true:true:true",
            "status:healthy:repair-vm-disk:VM disk repaired. Previous disk archive: \(archivedDisk.path)",
        ])
    }

    func testRepairUsesDefaultSizeWhenCurrentDiskIsMissing() throws {
        let harness = try VMDiskRepairHarness()
        try harness.write(harness.rootfsBase, bytes: 2)

        try harness.composition.repair()

        XCTAssertEqual(try harness.fileSize(harness.vmDisk), harness.bytesPerGiB * 32)
        XCTAssertTrue(harness.events.contains("log:vm disk missing; creating replacement without archive"))
    }

    func testRepairContinuesWhenRedisBackupFailsBecauseDiskIsStillArchived() throws {
        let harness = try VMDiskRepairHarness()
        harness.redisBackupError = TestError.backupFailed
        try harness.write(harness.rootfsBase, bytes: 2)
        try harness.write(harness.vmDisk, bytes: harness.bytesPerGiB * 32)

        try harness.composition.repair()

        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(harness.archivedDisk).path))
        XCTAssertTrue(harness.events.contains("status:recovering:repair-vm-disk:Redis backup before VM disk repair failed; current VM disk will be archived before replacement"))
    }

    func testRepairFailsBeforeRestartWhenReplacementDiskIsMissing() throws {
        let harness = try VMDiskRepairHarness()
        harness.dropReplacementDiskAfterMove = true
        try harness.write(harness.rootfsBase, bytes: 2)

        XCTAssertThrowsError(try harness.composition.repair()) { error in
            XCTAssertEqual(
                String(describing: error),
                "vm disk repair replacement missing path=\(harness.vmDisk.path)"
            )
        }
        XCTAssertFalse(harness.events.contains { $0.hasPrefix("start:") })
        XCTAssertFalse(harness.events.contains { $0.hasPrefix("wait:") })
    }
}

private final class VMDiskRepairHarness {
    let root: URL
    let installedPaths: InstalledRuntimePaths
    let runtimeDirectory: URL
    let backupsDirectory: URL
    let rootfsBase: URL
    let vmDisk: URL
    let bytesPerGiB: UInt64 = 1024 * 1024 * 1024
    var events: [String] = []
    var archivedDisk: URL?
    var redisBackupError: Error?
    var dropReplacementDiskAfterMove = false

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeVMDiskRepairCompositionTests-\(UUID().uuidString)")
        installedPaths = InstalledRuntimePaths(runtimeHome: root.appendingPathComponent("vm"))
        runtimeDirectory = installedPaths.runtimeDirectory
        backupsDirectory = installedPaths.backupsDirectory
        rootfsBase = runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase)
        vmDisk = runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var composition: RuntimeVMDiskRepairComposition {
        RuntimeVMDiskRepairComposition(
            context: RuntimeVMDiskRepairCompositionContext(
                installedPaths: installedPaths
            ),
            operations: RuntimeVMDiskRepairCompositionOperations(
                fileStore: ObservingRuntimeFileStore(
                    events: { [self] event in events.append(event) },
                    archivedDisk: { [self] url in archivedDisk = url },
                    dropReplacementDiskAfterMove: { [self] in dropReplacementDiskAfterMove },
                    vmDisk: vmDisk
                ),
                requireFreeSpace: { [self] url, minimumBytes, operation in
                    events.append("space:\(url.lastPathComponent):\(minimumBytes):\(operation)")
                },
                runProcessToFile: { [self] executable, arguments, output in
                    events.append("\(URL(fileURLWithPath: executable).lastPathComponent):\(arguments.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " ")):\(output.lastPathComponent)")
                    try write(output, bytes: bytesPerGiB * 4)
                },
                runRequired: { [self] executable, arguments in
                    events.append("\(URL(fileURLWithPath: executable).lastPathComponent):\(arguments.joined(separator: " "))")
                    if URL(fileURLWithPath: executable).lastPathComponent == "truncate",
                       let sizeArgument = arguments.dropFirst().first,
                       let gib = UInt64(sizeArgument.dropLast()) {
                        try write(URL(fileURLWithPath: arguments.last!), bytes: bytesPerGiB * gib)
                    }
                },
                createRedisBackup: { [self] in
                    events.append("redis-backup")
                    if let redisBackupError {
                        throw redisBackupError
                    }
                },
                stopRuntimeServicesForVMDiskReplacement: { [self] in
                    events.append("stop-for-disk-replacement")
                },
                startRuntimeServices: { [self] policy in
                    events.append("start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
                },
                waitForHealth: { [self] policy in
                    events.append("wait:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
                },
                writeStatus: { [self] status, operation, message in
                    events.append("status:\(status.rawValue):\(operation.rawValue):\(message)")
                },
                timestamp: { "20260529T081838Z" },
                log: { [self] message in
                    events.append("log:\(message)")
                }
            )
        )
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    func write(_ url: URL, bytes: UInt64) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: bytes)
        try handle.close()
    }
}

private struct ObservingRuntimeFileStore: RuntimeFileStore {
    var events: (String) -> Void
    var archivedDisk: (URL) -> Void
    var dropReplacementDiskAfterMove: () -> Bool
    var vmDisk: URL
    private let store = SystemRuntimeFileStore()

    var temporaryDirectory: URL {
        store.temporaryDirectory
    }

    func fileExists(_ url: URL) -> Bool {
        store.fileExists(url)
    }

    func directoryExists(_ url: URL) -> Bool {
        store.directoryExists(url)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        store.isExecutableFile(atPath: path)
    }

    func readData(_ url: URL) throws -> Data {
        try store.readData(url)
    }

    func readUTF8Text(_ url: URL) throws -> String {
        try store.readUTF8Text(url)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        try store.fileSize(url)
    }

    func modificationDate(_ url: URL) throws -> Date {
        try store.modificationDate(url)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try store.writeData(data, to: url, options: options)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {
        try store.writeData(data, to: url, options: options, posixPermissions: posixPermissions)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        events("mkdir:\(url.lastPathComponent):\(withIntermediateDirectories)")
        try store.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    func removeItem(at url: URL) throws {
        events("remove:\(url.lastPathComponent)")
        try store.removeItem(at: url)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try store.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        events("move:\(source.lastPathComponent):\(destination.lastPathComponent)")
        if destination.deletingLastPathComponent().lastPathComponent.hasPrefix("vm-disk-repair") {
            archivedDisk(destination)
        }
        try store.moveItem(at: source, to: destination)
        if dropReplacementDiskAfterMove(), destination == vmDisk {
            try store.removeItem(at: destination)
        }
    }

    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        try store.contentsOfDirectory(at: url, skipsHiddenFiles: skipsHiddenFiles)
    }

    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        try store.childDirectories(at: url, nameContains: fragment, skipsHiddenFiles: skipsHiddenFiles)
    }

    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        try store.recursiveRegularFileSize(at: url, skipsHiddenFiles: skipsHiddenFiles)
    }

    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        try store.fileSystemAttributes(forPath: path)
    }
}

private enum TestError: Error {
    case backupFailed
}
