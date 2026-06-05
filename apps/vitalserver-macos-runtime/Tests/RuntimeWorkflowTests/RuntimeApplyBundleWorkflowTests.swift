import Contracts
import Core
import Foundation
import RuntimeWorkflow
import XCTest

final class RuntimeApplyBundleWorkflowTests: XCTestCase {
    func testApplyBundleComposesPreflightAndStepExecutorPorts() throws {
        let harness = ApplyBundleWorkflowHarness()

        try harness.workflow.applyBundle(harness.inputBundle)

        XCTAssertEqual(harness.stageBundleInputs, [harness.inputBundle])
        XCTAssertEqual(harness.loadedManifests, [harness.stagedBundle.appendingPathComponent(RuntimeFileNames.updateBundleManifest)])
        XCTAssertEqual(harness.createdDirectories.map(\.url), [harness.logsDirectory, harness.backupsDirectory])
        XCTAssertEqual(harness.freeSpaceRequests.map(\.operation), [.applyBundle])
        XCTAssertEqual(harness.backupReasons, ["before-0.2.0"])
        XCTAssertEqual(harness.stepCalls, [
            "stopRuntimeServices",
            "replaceUpdateArtifacts",
            "runMigrations",
            "refreshCloudInitSeedIfNeeded",
            "writeRuntimeVersion",
            "startRuntimeServices",
            "activateGuestUpdateIfNeeded",
            "waitForHealth",
        ])
        XCTAssertEqual(harness.statuses.last?.level, .healthy)
        XCTAssertEqual(harness.statuses.last?.operation, .applyBundle)
        XCTAssertEqual(harness.statuses.last?.message, "bundle applied: 0.2.0")
        XCTAssertEqual(harness.pruneCount, 1)
        XCTAssertTrue(harness.logs.contains("mutable VM disk preserved path=\(harness.vmDisk.path)"))
    }

    func testApplyBundleRecordsLogPreparationFailuresWithoutFailingApply() throws {
        let harness = ApplyBundleWorkflowHarness()
        harness.createDirectoryErrors[harness.logsDirectory] = CocoaError(.fileWriteNoPermission)
        harness.rotateRuntimeLogsError = TestApplyBundleWorkflowError.rotation

        try harness.workflow.applyBundle(harness.inputBundle)

        XCTAssertEqual(harness.statuses.last?.level, .healthy)
        XCTAssertTrue(harness.logs.contains { $0.contains("bundle apply log directory preparation failed") })
        XCTAssertTrue(harness.logs.contains { $0.contains("bundle apply log rotation failed") })
    }
}

private final class ApplyBundleWorkflowHarness {
    let inputBundle = URL(fileURLWithPath: "/tmp/input-bundle")
    let stagedBundle = URL(fileURLWithPath: "/product/bundles/update-bundle-0.2.0")
    let backupsDirectory = URL(fileURLWithPath: "/product/backups")
    let logsDirectory = URL(fileURLWithPath: "/product/logs")
    let rootfsBase = URL(fileURLWithPath: "/product/rootfs-base.raw.gz")
    let vmDisk = URL(fileURLWithPath: "/product/vm-disk.img")
    let backup = URL(fileURLWithPath: "/product/backups/backup-before-0.2.0")
    let restartPolicy = RuntimeServiceRestartPolicy(
        restartVM: false,
        restartGuestLogSync: true,
        restartProxy: true,
        restartWatchdog: false
    )
    let manifest = UpdateBundleManifest(
        schemaVersion: 3,
        product: "ai.tirosh.vitalserver.helper",
        helperVersion: "0.2.0",
        releaseLabel: "0.2.0",
        targetPlatform: "macos-arm64",
        components: ["updater": "0.2.0"],
        createdAt: "2026-06-01T00:00:00Z",
        artifacts: [],
        migrations: []
    )

    var stageBundleInputs: [URL] = []
    var loadedManifests: [URL] = []
    var createdDirectories: [(url: URL, withIntermediateDirectories: Bool)] = []
    var createDirectoryErrors: [URL: Error] = [:]
    var freeSpaceRequests: [(url: URL, bytes: UInt64, operation: RuntimeOperation)] = []
    var backupReasons: [String] = []
    var stepCalls: [String] = []
    var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
    var progressEvents: [RuntimeStepExecutionEvent] = []
    var logs: [String] = []
    var pruneCount = 0
    var rotateRuntimeLogsError: Error?

    var workflow: RuntimeApplyBundleWorkflow {
        RuntimeApplyBundleWorkflow(
            context: RuntimeApplyBundleWorkflowContext(
                backupsDirectory: backupsDirectory,
                logsDirectory: logsDirectory,
                rootfsBase: rootfsBase,
                vmDisk: vmDisk,
                updateFreeSpaceMarginBytes: 10
            ),
            operations: RuntimeApplyBundleWorkflowOperations(
                stageBundle: { url in
                    self.stageBundleInputs.append(url)
                    return self.stagedBundle
                },
                loadManifest: { url in
                    self.loadedManifests.append(url)
                    return self.manifest
                },
                fileExists: { _ in true },
                createDirectory: { url, withIntermediateDirectories in
                    if let error = self.createDirectoryErrors[url] {
                        throw error
                    }
                    self.createdDirectories.append((url: url, withIntermediateDirectories: withIntermediateDirectories))
                },
                fileSize: { _ in 1 },
                directorySize: { url in
                    url == self.backup ? 5 : 42
                },
                requireFreeSpace: { url, bytes, operation in
                    self.freeSpaceRequests.append((url: url, bytes: bytes, operation: operation))
                },
                checkCompatibility: { _ in },
                serviceRestartPolicy: {
                    self.restartPolicy
                },
                runtimeHealthSnapshot: {
                    Self.healthSnapshot()
                },
                requireGuestCapability: { _ in
                    XCTFail("guest capability should not be required when VM is not being restarted and bundle has no guest deploy")
                },
                createBackup: { reason in
                    self.backupReasons.append(reason)
                    return self.backup
                },
                rotateRuntimeLogs: {
                    if let error = self.rotateRuntimeLogsError {
                        throw error
                    }
                },
                rollback: { _ in },
                startRuntimeServices: { _ in
                    self.stepCalls.append("startRuntimeServices")
                },
                statusReporter: RuntimeWorkflowStatusReporter(
                    writeStatus: { level, operation, message in
                        self.statuses.append((level: level, operation: operation, message: message))
                    },
                    writeProgress: { event in
                        self.progressEvents.append(event)
                    },
                    log: { message in
                        self.logs.append(message)
                    }
                ),
                pruneOldRuntimeArtifacts: {
                    self.pruneCount += 1
                },
                reasonText: { reasons in
                    reasons.map(\.rawValue).joined(separator: ", ")
                },
                stopRuntimeServices: {
                    self.stepCalls.append("stopRuntimeServices")
                },
                runningVMProcessID: {
                    XCTFail("VM pid should not be read when restartVM is false")
                    return 0
                },
                stopRuntimeServicesAfterGuestPoweroff: { _ in
                    XCTFail("guest poweroff path should not run when restartVM is false")
                },
                prepareGuestShutdownForUpdate: { _ in
                    XCTFail("guest shutdown preparation should not run when restartVM is false")
                },
                clearGuestShutdownPreparation: {},
                replaceFile: { _, _ in
                    XCTFail("rootfs replacement should not run without a staged rootfs")
                },
                replaceUpdateArtifacts: { _, _ in
                    self.stepCalls.append("replaceUpdateArtifacts")
                },
                runMigrations: { _, _ in
                    self.stepCalls.append("runMigrations")
                },
                refreshCloudInitSeedIfNeeded: { _ in
                    self.stepCalls.append("refreshCloudInitSeedIfNeeded")
                },
                writeRuntimeVersion: { version, stagedBundle in
                    XCTAssertEqual(version, "0.2.0")
                    XCTAssertEqual(stagedBundle, self.stagedBundle)
                    self.stepCalls.append("writeRuntimeVersion")
                },
                activateGuestUpdateIfNeeded: { _ in
                    self.stepCalls.append("activateGuestUpdateIfNeeded")
                },
                waitForHealth: { _ in
                    self.stepCalls.append("waitForHealth")
                },
                log: { message in
                    self.logs.append(message)
                }
            )
        )
    }

    private static func healthSnapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmIP: "192.168.64.2",
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            failureReasons: []
        )
    }
}

private enum TestApplyBundleWorkflowError: Error {
    case rotation
}
