import Contracts
import Core
import Foundation
import RuntimeWorkflow
import XCTest

final class RuntimeVMDiskRepairWorkflowTests: XCTestCase {
    func testRepairArchivesCurrentDiskAndCreatesReplacementBeforeRestart() throws {
        let harness = try VMDiskRepairHarness()
        try harness.write(harness.rootfsBase, bytes: 2)
        try harness.write(harness.vmDisk, bytes: harness.bytesPerGiB * 40)

        try harness.runner.repair()

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
            "space:runtime:1036:repair-vm-disk",
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

        try harness.runner.repair()

        XCTAssertEqual(try harness.fileSize(harness.vmDisk), harness.bytesPerGiB * 32)
        XCTAssertTrue(harness.events.contains("log:vm disk missing; creating replacement without archive"))
    }

    func testRepairContinuesWhenRedisBackupFailsBecauseDiskIsStillArchived() throws {
        let harness = try VMDiskRepairHarness()
        harness.redisBackupError = TestError.backupFailed
        try harness.write(harness.rootfsBase, bytes: 2)
        try harness.write(harness.vmDisk, bytes: harness.bytesPerGiB * 32)

        try harness.runner.repair()

        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(harness.archivedDisk).path))
        XCTAssertTrue(harness.events.contains("status:recovering:repair-vm-disk:Redis backup before VM disk repair failed; current VM disk will be archived before replacement"))
    }

    func testRepairFailsBeforeRestartWhenReplacementDiskIsMissing() throws {
        let harness = try VMDiskRepairHarness()
        harness.dropReplacementDiskAfterMove = true
        try harness.write(harness.rootfsBase, bytes: 2)

        XCTAssertThrowsError(try harness.runner.repair()) { error in
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
    let runtimeDirectory: URL
    let backupsDirectory: URL
    let rootfsBase: URL
    let vmDisk: URL
    let bytesPerGiB: UInt64 = 1024
    var events: [String] = []
    var archivedDisk: URL?
    var redisBackupError: Error?
    var dropReplacementDiskAfterMove = false

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeVMDiskRepairRunnerTests-\(UUID().uuidString)")
        runtimeDirectory = root.appendingPathComponent("runtime")
        backupsDirectory = root.appendingPathComponent("backups")
        rootfsBase = runtimeDirectory.appendingPathComponent("rootfs-base.raw.gz")
        vmDisk = runtimeDirectory.appendingPathComponent("vm-disk.img")
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var runner: RuntimeVMDiskRepairRunner {
        RuntimeVMDiskRepairRunner(
            context: RuntimeVMDiskRepairContext(
                rootfsBase: rootfsBase,
                vmDisk: vmDisk,
                backupsDirectory: backupsDirectory,
                defaultDiskGiB: 32,
                bytesPerGiB: bytesPerGiB,
                freeSpaceMarginBytes: 1024,
                gunzipExecutable: "/usr/bin/gunzip",
                truncateExecutable: "/usr/bin/truncate"
            ),
            operations: RuntimeVMDiskRepairOperations(
                fileExists: fileExists,
                fileSize: fileSize,
                createDirectory: { [self] url, withIntermediateDirectories in
                    events.append("mkdir:\(url.lastPathComponent):\(withIntermediateDirectories)")
                    try FileManager.default.createDirectory(
                        at: url,
                        withIntermediateDirectories: withIntermediateDirectories
                    )
                },
                removeItem: { [self] url in
                    events.append("remove:\(url.lastPathComponent)")
                    try FileManager.default.removeItem(at: url)
                },
                moveItem: { [self] source, destination in
                    events.append("move:\(source.lastPathComponent):\(destination.lastPathComponent)")
                    if destination.deletingLastPathComponent().lastPathComponent.hasPrefix("vm-disk-repair") {
                        archivedDisk = destination
                    }
                    try FileManager.default.moveItem(at: source, to: destination)
                    if dropReplacementDiskAfterMove, destination == vmDisk {
                        try FileManager.default.removeItem(at: destination)
                    }
                },
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

    func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
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

private enum TestError: Error {
    case backupFailed
}
