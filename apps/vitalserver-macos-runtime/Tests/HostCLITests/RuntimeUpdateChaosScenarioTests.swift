import Contracts
import Core
import Foundation
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeUpdateChaosScenarioTests: XCTestCase {
    func testGuestCapabilityChaosStopsPreflightBeforeManagedBackup() {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        var events: [String] = []
        let runner = RuntimeApplyBundlePreflightRunner(
            stageBundle: { _ in stagedBundle },
            loadManifest: { _ in
                self.manifest(
                    version: "1.2.3",
                    artifacts: [
                        UpdateBundleArtifact(
                            name: "guest-deploy.tar.gz",
                            type: .guestDeploy,
                            sha256: "abc",
                            size: 20
                        ),
                    ]
                )
            },
            fileExists: { _ in false },
            createDirectory: { _, _ in events.append("mkdir") },
            fileSize: { _ in 0 },
            requireFreeSpace: { _, _, _ in events.append("space") },
            checkCompatibility: { _ in events.append("compatibility") },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: false)
            },
            runtimeHealthSnapshot: { self.healthySnapshot() },
            requireGuestCapability: { capability in
                events.append("capability:\(capability.rawValue)")
                if capability == .activateUpdate {
                    throw LauncherError.runtimeOperationFailed("guest capability missing: \(capability.rawValue)")
                }
            },
            createBackup: { _ in
                events.append("backup")
                return URL(fileURLWithPath: "/backup")
            },
            directorySize: { _ in 10 },
            log: { _ in }
        )

        XCTAssertThrowsError(try runner.prepare(
            bundleURL: URL(fileURLWithPath: "/incoming/bundle"),
            backupsDirectory: URL(fileURLWithPath: "/product/backups"),
            rootfsBase: URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        )) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: activate-update")
        }
        XCTAssertEqual(events, [
            "compatibility",
            "mkdir",
            "space",
            "policy",
            "capability:prepare-update-shutdown",
            "capability:activate-update",
        ])
    }

    func testUpdateArtifactChaosPreservesManagedStorageCopyFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        let source = URL(fileURLWithPath: "/input/update-bundle")
        try writeEmptyBundle(at: source, to: fileStore)
        fileStore.copyItemError = CocoaError(.fileWriteNoPermission)
        var logs: [String] = []
        let workflow = makeWorkflow(
            fileStore: fileStore,
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try workflow.stageBundle(source)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSCocoaErrorDomain)
            XCTAssertEqual(nsError.code, CocoaError.Code.fileWriteNoPermission.rawValue)
        }
        XCTAssertTrue(logs.contains { $0.contains("copying bundle to managed storage") })
    }

    func testGuestCapabilityReadChaosPreservesReadFailureReason() {
        let checker = RuntimeGuestCapabilityChecker(loadRuntimeState: {
            .failed("permission denied")
        })

        XCTAssertThrowsError(try checker.require(.prepareUpdateShutdown)) { error in
            XCTAssertEqual(
                String(describing: error),
                "failed to read guest runtime state for guest capability prepare-update-shutdown: permission denied"
            )
        }
    }

    func testCommandChaosRecordsStderrAndFailedEventBeforeThrowing() {
        let runner = ChaosCommandRunner(
            result: RuntimeProcessResult(exitCode: 13, stdout: "", stderr: "permission denied\n")
        )
        var logs: [String] = []
        var events: [(type: RuntimeEventType, result: RuntimeProcessResult?)] = []
        let executor = RuntimeCommandExecutor(
            commandRunner: runner,
            log: { logs.append($0) },
            recordCommandEvent: { type, _, _, result in
                events.append((type, result))
            }
        )

        XCTAssertThrowsError(try executor.runRequired("/bin/chmod", ["0755", "/restricted"])) { error in
            XCTAssertEqual(
                String(describing: error),
                "command failed: /bin/chmod 0755 /restricted"
            )
        }

        XCTAssertEqual(logs, [
            "command started executable=/bin/chmod arguments=0755 /restricted",
            "command stderr executable=/bin/chmod stderr=permission denied",
            "command failed executable=/bin/chmod exitCode=13",
        ])
        XCTAssertEqual(events.map(\.type), [.runtimeCommandStarted, .runtimeCommandFailed])
        XCTAssertEqual(events.last?.result?.exitCode, 13)
        XCTAssertEqual(events.last?.result?.stderr, "permission denied\n")
    }

    func testUpdateApplyChaosSeparatesApplyFailureFromRollbackFailure() {
        let preflight = applyPreflight(
            artifacts: [
                UpdateBundleArtifact(
                    name: "app.tar.gz",
                    type: .appBundle,
                    sha256: "sha256",
                    size: 10
                ),
            ]
        )
        var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
        var progressEvents: [RuntimeStepExecutionEvent] = []
        var executedSteps: [RuntimeWorkflowStep] = []
        var rollbackBackup: URL?
        var restartedPolicy: RuntimeServiceRestartPolicy?
        var logs: [String] = []
        let runner = RuntimeApplyBundleRunner(
            prepareLogs: {},
            initialHealthSnapshot: { Self.healthSnapshot() },
            preparePreflight: { _ in preflight },
            executeStep: { step, _ in
                executedSteps.append(step)
                if step == .replaceUpdateArtifacts {
                    throw RuntimeChaosError.applyArtifactWriteDenied
                }
            },
            rollback: { backup in
                rollbackBackup = backup
                throw RuntimeChaosError.rollbackRestoreDenied
            },
            startRuntimeServices: { policy in
                restartedPolicy = policy
            },
            statusReporter: RuntimeWorkflowStatusReporter(
                writeStatus: { level, operation, message in
                    statuses.append((level, operation, message))
                },
                writeProgress: { event in
                    progressEvents.append(event)
                },
                log: { message in
                    logs.append(message)
                }
            ),
            pruneOldRuntimeArtifacts: {},
            reasonText: { $0.map(\.rawValue).joined(separator: ", ") }
        )

        XCTAssertThrowsError(try runner.run(bundleURL: URL(fileURLWithPath: "/incoming/update-bundle"))) { error in
            XCTAssertEqual(String(describing: error), "applyArtifactWriteDenied")
        }

        XCTAssertEqual(rollbackBackup, preflight.backup)
        XCTAssertEqual(restartedPolicy, preflight.restartPolicy)
        XCTAssertTrue(executedSteps.contains(.replaceUpdateArtifacts))
        XCTAssertEqual(progressEvents.last?.step, .replaceUpdateArtifacts)
        XCTAssertEqual(progressEvents.last?.stepStatus, .failed)
        XCTAssertTrue(statuses.contains { $0.level == .recovering && $0.message.contains("applyArtifactWriteDenied") })
        XCTAssertEqual(statuses.last?.level, .critical)
        XCTAssertTrue(statuses.last?.message.contains("rollbackRestoreDenied") == true)
        XCTAssertTrue(logs.contains { $0.contains("bundle apply failed; rolling back error=applyArtifactWriteDenied") })
        XCTAssertTrue(logs.contains { $0.contains("bundle apply rollback failed error=rollbackRestoreDenied") })
    }

    func testRollbackChaosPublishesFailedRestoreStepAndKeepsRecoveringStatus() {
        let preflight = rollbackPreflight()
        var statuses: [(level: RuntimeStatusLevel, operation: RuntimeOperation, message: String)] = []
        var progressEvents: [RuntimeStepExecutionEvent] = []
        var executedSteps: [RuntimeWorkflowStep] = []
        let runner = RuntimeRollbackRunner(
            preparePreflight: { _ in preflight },
            executeStep: { step, _ in
                executedSteps.append(step)
                if step == .rollbackRestoreRootfsBase {
                    throw RuntimeChaosError.rollbackRestoreDenied
                }
            },
            writeStatus: { level, operation, message in
                statuses.append((level, operation, message))
            },
            writeProgress: { event in
                progressEvents.append(event)
            },
            vmDiskPath: { "/product/vm/vm-disk.img" },
            log: { _ in }
        )

        XCTAssertThrowsError(try runner.run(.specificBackup(preflight.backup))) { error in
            XCTAssertEqual(String(describing: error), "rollbackRestoreDenied")
        }

        XCTAssertEqual(executedSteps, [.rollbackStopRuntimeServices, .rollbackRestoreRootfsBase])
        XCTAssertEqual(progressEvents.last?.step, .rollbackRestoreRootfsBase)
        XCTAssertEqual(progressEvents.last?.stepStatus, .failed)
        XCTAssertEqual(statuses.last?.level, .recovering)
        XCTAssertEqual(statuses.last?.operation, .rollback)
    }

    func testGuestResultChaosSeparatesInvalidResultFromTimeout() {
        let invalidResult = GuestActivationWaiter.wait(
            expectedRequestId: "request-current",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 1, progressEveryAttempts: 1),
            loadResult: {
                .loaded(GuestUpdateActivationResultDocument(
                    schemaVersion: 2,
                    requestId: "request-stale",
                    operation: .activateGuestUpdate,
                    status: .completed,
                    message: "stale success",
                    updatedAt: "2026-05-31T00:00:00Z"
                ))
            },
            onProgress: { _ in },
            sleep: {}
        )
        var progressMessages: [String] = []
        var sleepCount = 0
        let timeoutResult = GuestActivationWaiter.wait(
            expectedRequestId: "request-current",
            configuration: GuestActivationWaitConfiguration(maxAttempts: 2, progressEveryAttempts: 1),
            loadResult: { .missing },
            onProgress: { progressMessages.append($0) },
            sleep: { sleepCount += 1 }
        )

        XCTAssertEqual(invalidResult, .failed(message: "guest update activation result does not match the current request"))
        XCTAssertEqual(timeoutResult, .timedOut)
        XCTAssertEqual(progressMessages, [
            "waiting for guest update activation worker",
            "waiting for guest update activation worker",
        ])
        XCTAssertEqual(sleepCount, 1)
    }

    func testRollbackPreflightChaosStopsWhenRestoreArtifactIsMissing() {
        let backup = URL(fileURLWithPath: "/product/backups/20260531T000000Z-before-1.2.3")
        let missingRootfs = backup.appendingPathComponent(Constants.Artifacts.rootfsBase)
        let runner = RuntimeRollbackPreflightRunner(
            requireLatestBackup: {
                XCTFail("specific backup should not resolve latest backup")
                return URL(fileURLWithPath: "/unused")
            },
            directoryExists: { url in url == backup },
            fileExists: { _ in false },
            loadManifest: { _ in
                BackupManifest(
                    product: Constants.Product.identifier,
                    createdAt: "2026-05-31T00:00:00Z",
                    reason: "before-1.2.3",
                    rootfsBase: Constants.Artifacts.rootfsBase,
                    vmDisk: Constants.BootAssets.disk,
                    vmDiskPreserved: true
                )
            },
            serviceRestartPolicy: {
                XCTFail("missing restore artifact should stop before service policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
            },
            log: { _ in XCTFail("missing restore artifact should stop before logging") }
        )

        XCTAssertThrowsError(try runner.prepare(.specificBackup(backup))) { error in
            XCTAssertEqual(String(describing: error), String(describing: LauncherError.missingFile(missingRootfs.path)))
        }
    }

    func testBackupChaosStopsBeforeManifestWhenManagedArtifactCopyIsDenied() {
        let paths = backupStorePaths()
        var createdDirectories: [URL] = []
        var wroteManifest = false
        let store = RuntimeBackupStore(
            paths: paths,
            timestamp: { "20260531T000000Z" },
            isoTimestamp: { "2026-05-31T00:00:00Z" },
            fileExists: { url in url == paths.rootfsBase },
            directoryExists: { _ in false },
            createDirectory: { url, _ in
                createdDirectories.append(url)
            },
            copyItem: { _, _ in
                throw RuntimeChaosError.backupWriteDenied
            },
            removeItem: { _ in },
            writeData: { _, _ in
                wroteManifest = true
            },
            contentsOfDirectory: { _ in [] },
            childDirectories: { _, _ in [] },
            chmodExecutable: { _ in },
            log: { _ in }
        )

        XCTAssertThrowsError(try store.createBackup(reason: "before-1.2.3")) { error in
            XCTAssertEqual(String(describing: error), "backupWriteDenied")
        }

        XCTAssertEqual(createdDirectories, [
            URL(fileURLWithPath: "/product/backups/20260531T000000Z-before-1.2.3"),
        ])
        XCTAssertFalse(wroteManifest)
    }

    private func makeWorkflow(
        fileStore: RuntimeFileStore,
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeBundleWorkflow {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        return RuntimeBundleWorkflow(
            context: RuntimeBundleWorkflowContext(
                installedPaths: installedPaths,
                bundlesDirectory: URL(fileURLWithPath: "/product/bundles"),
                backupsDirectory: URL(fileURLWithPath: "/product/backups"),
                logsDirectory: URL(fileURLWithPath: "/product/logs"),
                rootfsBase: URL(fileURLWithPath: "/product/rootfs-base.raw.gz"),
                vmDisk: URL(fileURLWithPath: "/product/vm-disk.img")
            ),
            operations: RuntimeBundleWorkflowOperations(
                fileStore: fileStore,
                runtimeHealthSnapshot: { Self.healthSnapshot() },
                rotateRuntimeLogs: {},
                rollback: { _ in },
                startRuntimeServices: { _ in },
                stopRuntimeServices: {},
                runningVMProcessID: { 123 },
                stopRuntimeServicesAfterGuestPoweroff: { _ in },
                prepareGuestShutdownForUpdate: { _ in },
                clearGuestShutdownPreparation: {},
                isLaunchdLoaded: { _ in false },
                createBackup: { _ in URL(fileURLWithPath: "/product/backups/backup") },
                statusReporter: RuntimeWorkflowStatusReporter(
                    writeStatus: { _, _, _ in },
                    writeProgress: { _ in },
                    log: log
                ),
                pruneOldRuntimeArtifacts: {},
                reasonText: { _ in "" },
                requireFreeSpace: { _, _, _ in },
                runProcess: { _, _ in RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "") },
                runRequired: { _, _ in },
                runProcessToFile: { _, _, _ in },
                replaceFile: { _, _ in },
                writeRuntimeVersion: { _, _ in },
                refreshCloudInitSeedIfNeeded: { _ in },
                activateGuestUpdateIfNeeded: { _ in },
                waitForHealth: { _ in },
                requireGuestCapability: { _ in },
                log: log
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

    private func manifest(
        version: String,
        artifacts: [UpdateBundleArtifact] = []
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: Constants.Product.identifier,
            helperVersion: version,
            releaseLabel: version,
            targetPlatform: "macos-arm64",
            components: ["updater": version],
            createdAt: "2026-05-31T00:00:00Z",
            artifacts: artifacts,
            migrations: []
        )
    }

    private func writeEmptyBundle(at source: URL, to fileStore: RuntimeFileStoreSpy) throws {
        fileStore.directories.insert(source)
        fileStore.files[source.appendingPathComponent(Constants.Bundle.manifest)] = try JSONEncoder().encode(
            manifest(version: "1.2.3")
        )
        fileStore.files[source.appendingPathComponent(Constants.Bundle.checksums)] = Data()
        fileStore.files[source.appendingPathComponent(Constants.Bundle.signature)] = Data("signature".utf8)
    }

    private func applyPreflight(artifacts: [UpdateBundleArtifact]) -> ApplyBundlePreflightContext {
        ApplyBundlePreflightContext(
            stagedBundle: URL(fileURLWithPath: "/managed/update-bundle-1.2.3"),
            manifest: manifest(version: "1.2.3", artifacts: artifacts),
            stagedRootfs: nil,
            backup: URL(fileURLWithPath: "/product/backups/20260531T000000Z-before-1.2.3"),
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: true, restartWatchdog: false)
        )
    }

    private func rollbackPreflight() -> RollbackPreflightContext {
        let backup = URL(fileURLWithPath: "/product/backups/20260531T000000Z-before-1.2.3")
        return RollbackPreflightContext(
            backup: backup,
            backupRootfs: backup.appendingPathComponent(Constants.Artifacts.rootfsBase),
            backupVersion: backup.appendingPathComponent(Constants.Artifacts.runtimeVersion),
            restoresRootfsBase: true,
            restartPolicy: RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: true)
        )
    }

    private func backupStorePaths() -> RuntimeBackupStorePaths {
        RuntimeBackupStorePaths(
            backupsDirectory: URL(fileURLWithPath: "/product/backups"),
            rootfsBase: URL(fileURLWithPath: "/product/vm/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/product/vm/runtime/runtime-version.json"),
            managerApp: URL(fileURLWithPath: "/Applications/VitalServer Helper.app"),
            nginxBundle: URL(fileURLWithPath: "/product/nginx"),
            guestDeploy: URL(fileURLWithPath: "/product/vm/data/deploy"),
            runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
        )
    }

    private func healthySnapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: true,
            proxyExecutable: true,
            rootfsBase: .present,
            vmDisk: .present,
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmState: .running,
            vmErrors: [],
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

private enum RuntimeChaosError: Error, CustomStringConvertible {
    case applyArtifactWriteDenied
    case rollbackRestoreDenied
    case backupWriteDenied

    var description: String {
        switch self {
        case .applyArtifactWriteDenied:
            return "applyArtifactWriteDenied"
        case .rollbackRestoreDenied:
            return "rollbackRestoreDenied"
        case .backupWriteDenied:
            return "backupWriteDenied"
        }
    }
}

private final class ChaosCommandRunner: RuntimeCommandRunner {
    let result: RuntimeProcessResult

    init(result: RuntimeProcessResult) {
        self.result = result
    }

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        result
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        result
    }
}
