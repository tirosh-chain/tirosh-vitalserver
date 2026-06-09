import Contracts
import Foundation
import Workflow
import XCTest

final class RuntimeVMDiskRepairWorkflowTests: XCTestCase {
    func testRepairWritesDegradedStatusAndRethrowsWhenHealthWaitFails() throws {
        let harness = VMDiskRepairWorkflowHarness()
        harness.files[harness.rootfsBase] = 2
        harness.files[harness.vmDisk] = harness.bytesPerGiB * 40
        harness.waitError = VMDiskRepairWorkflowTestError.healthWaitFailed

        XCTAssertThrowsError(try harness.run()) { error in
            XCTAssertEqual(error as? VMDiskRepairWorkflowTestError, .healthWaitFailed)
        }

        XCTAssertEqual(harness.statuses.map(\.level), [
            .recovering,
            .recovering,
            .recovering,
            .recovering,
            .recovering,
            .recovering,
            .degraded,
        ])
        XCTAssertTrue(harness.events.contains("start:true:true:true"))
        XCTAssertTrue(harness.events.contains("wait:true:true:true"))
        XCTAssertTrue(harness.logs.contains { $0.contains("archived vm disk path=") })
    }

    func testMissingRootfsStopsBeforeStatusOrEffects() {
        let harness = VMDiskRepairWorkflowHarness()

        XCTAssertThrowsError(try harness.run()) { error in
            XCTAssertEqual(String(describing: error), "missing file: \(harness.rootfsBase.path)")
        }

        XCTAssertTrue(harness.statuses.isEmpty)
        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertTrue(harness.logs.isEmpty)
    }

    func testUnexpectedRootfsPathStateStopsBeforeStatusOrEffects() {
        let harness = VMDiskRepairWorkflowHarness()
        harness.directories.insert(harness.rootfsBase)

        XCTAssertThrowsError(try harness.run()) { error in
            XCTAssertEqual(
                String(describing: error),
                "rootfs base path state is unexpected: \(harness.rootfsBase.path) state=directory"
            )
        }

        XCTAssertTrue(harness.statuses.isEmpty)
        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertTrue(harness.logs.isEmpty)
    }

    func testRedisBackupFailureResultContinuesWithExplicitReason() throws {
        let harness = VMDiskRepairWorkflowHarness()
        harness.files[harness.rootfsBase] = 2
        harness.files[harness.vmDisk] = harness.bytesPerGiB * 32
        harness.redisBackupFailureReason = "permission denied"

        try harness.run()

        XCTAssertTrue(harness.logs.contains(
            "redis backup before vm disk repair failed error=permission denied; continuing with VM disk archive"
        ))
        XCTAssertTrue(harness.statuses.contains {
            $0.level == .recovering
                && $0.operation == .repairVMDisk
                && $0.message == "Redis backup before VM disk repair failed; current VM disk will be archived before replacement"
        })
    }

    func testStopFailureWritesCriticalStatusBeforeRethrow() {
        let harness = VMDiskRepairWorkflowHarness()
        harness.files[harness.rootfsBase] = 2
        harness.files[harness.vmDisk] = harness.bytesPerGiB * 32
        harness.stopError = VMDiskRepairWorkflowTestError.serviceStopFailed

        XCTAssertThrowsError(try harness.run()) { error in
            XCTAssertEqual(
                String(describing: error),
                "VM disk repair failed before archive; runtime services did not stop. reason=serviceStopFailed"
            )
        }

        XCTAssertEqual(harness.statuses.last?.level, .critical)
        XCTAssertEqual(harness.statuses.last?.operation, .repairVMDisk)
        XCTAssertEqual(
            harness.statuses.last?.message,
            "VM disk repair failed before archive; runtime services did not stop. reason=serviceStopFailed"
        )
        XCTAssertTrue(harness.events.contains("stop-for-disk-replacement"))
        XCTAssertFalse(harness.events.contains { $0.hasPrefix("move:vm-disk.img:") })
        XCTAssertFalse(harness.events.contains { $0.hasPrefix("start:") })
    }
}

private final class VMDiskRepairWorkflowHarness {
    let root = URL(fileURLWithPath: "/workflow-test")
    let bytesPerGiB: UInt64 = 1024
    lazy var runtimeDirectory = root.appendingPathComponent("runtime")
    lazy var rootfsBase = runtimeDirectory.appendingPathComponent("rootfs-base.raw.gz")
    lazy var vmDisk = runtimeDirectory.appendingPathComponent("vm-disk.img")
    lazy var backupsDirectory = root.appendingPathComponent("backups")
    var files: [URL: UInt64] = [:]
    var directories: Set<URL> = []
    var events: [String] = []
    var logs: [String] = []
    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var waitError: Error?
    var stopError: Error?
    var redisBackupFailureReason: String?

    func run() throws {
        try RuntimeVMDiskRepairWorkflow().repair(
            context: RuntimeVMDiskRepairContext(
                rootfsBase: rootfsBase,
                vmDisk: vmDisk,
                backupsDirectory: backupsDirectory,
                defaultDiskGiB: 32,
                bytesPerGiB: bytesPerGiB,
                freeSpaceMarginBytes: 10
            ),
            operations: RuntimeVMDiskRepairOperations(
                pathState: { [self] url in
                    if files[url] != nil {
                        return .file
                    }
                    if directories.contains(url) {
                        return .directory
                    }
                    return .missing
                },
                fileSize: { [self] url in
                    guard let size = files[url] else {
                        throw VMDiskRepairWorkflowTestError.missingFileSize
                    }
                    return size
                },
                createDirectory: { [self] url, withIntermediateDirectories in
                    events.append("mkdir:\(url.lastPathComponent):\(withIntermediateDirectories)")
                    directories.insert(url)
                },
                removeItem: { [self] url in
                    events.append("remove:\(url.lastPathComponent)")
                    files[url] = nil
                    directories.remove(url)
                },
                moveItem: { [self] source, destination in
                    events.append("move:\(source.lastPathComponent):\(destination.lastPathComponent)")
                    files[destination] = files[source]
                    files[source] = nil
                },
                requireFreeSpace: { [self] url, minimumBytes, operation in
                    events.append("space:\(url.lastPathComponent):\(minimumBytes):\(operation)")
                },
                createReplacementVMDisk: { [self] plan in
                    events.append("create-replacement:\(plan.rootfsBase.lastPathComponent):\(plan.targetDiskGiB):\(plan.temporaryDisk.lastPathComponent)")
                    files[plan.temporaryDisk] = bytesPerGiB * UInt64(plan.targetDiskGiB)
                },
                createRedisBackup: { [self] in
                    events.append("redis-backup")
                    if let redisBackupFailureReason {
                        return .failed(reason: redisBackupFailureReason)
                    }
                    return .completed
                },
                stopRuntimeServicesForVMDiskReplacement: { [self] in
                    events.append("stop-for-disk-replacement")
                    if let stopError {
                        return .failed(reason: String(describing: stopError))
                    }
                    return .completed
                },
                startRuntimeServices: { [self] policy in
                    events.append("start:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
                },
                waitForHealth: { [self] policy in
                    events.append("wait:\(policy.restartVM):\(policy.restartProxy):\(policy.restartWatchdog)")
                    if let waitError {
                        throw waitError
                    }
                },
                writeStatus: { [self] level, operation, message in
                    statuses.append((level, operation, message))
                },
                timestamp: { "20260529T081838Z" },
                log: { [self] message in logs.append(message) }
            )
        )
    }
}

private enum VMDiskRepairWorkflowTestError: Error {
    case healthWaitFailed
    case serviceStopFailed
    case missingFileSize
}
