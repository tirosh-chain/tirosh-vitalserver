import Contracts
import Application
import Bootstrap
import Domain
import Foundation
import OutboundAdapters
import InboundAdapters
import Workflow
@testable import CLIHost
import XCTest
import Errors

final class RuntimeUpdateChaosScenarioTests: XCTestCase {
    func testGuestCapabilityChaosStopsPreflightBeforeManagedBackup() {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        var events: [String] = []
        let operations = ApplyRuntimeBundlePreflightOperations(
            stageBundle: { _ in stagedBundle },
            loadStagedManifest: { _ in
                self.manifest(
                    version: "1.2.3",
                    artifacts: [
                        UpdateBundleArtifact(
                            name: "guest-deploy.tar.gz",
                            type: .guestDeploy,
                            sha256: "abc",
                            size: 20
                        ),
                    ],
                    requiresGuestActivation: true
                )
            },
            observeRootfsStorage: { _, _ in
                XCTFail("rootfs storage should not be observed")
                throw LauncherError.runtimeOperationFailed("unexpected rootfs storage observation")
            },
            createDirectory: { _, _ in events.append("mkdir") },
            requireFreeSpace: { _, _, _ in events.append("space") },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: false)
            },
            runtimeHealthSnapshot: {
                events.append("health")
                return Self.healthSnapshot()
            },
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

        XCTAssertThrowsError(try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: ApplyRuntimeBundlePreflightInput(
                bundleURL: URL(fileURLWithPath: "/incoming/bundle"),
                backupsDirectory: URL(fileURLWithPath: "/product/backups"),
                rootfsBase: URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz"),
                updateFreeSpaceMarginBytes: Constants.Runtime.updateFreeSpaceMarginBytes,
                currentUpdaterVersion: "1.0.0",
                currentChannel: .stable,
                currentPlatform: "macos-arm64"
            ),
            operations: operations
        )) { error in
            XCTAssertEqual(String(describing: error), "guest capability missing: activate-update")
        }
        XCTAssertEqual(events, [
            "mkdir",
            "space",
            "policy",
            "health",
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
        XCTAssertThrowsError(try RuntimeGuestCapabilityCheckerComposition.require(
            .prepareUpdateShutdown,
            guestControlGateway: RuntimeUpdateChaosGuestControlGateway(result: .failed("permission denied"))
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "failed to read guest capabilities for prepare-update-shutdown: permission denied"
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
        let operations = ApplyRuntimeBundleOperations(
            prepareLogs: {},
            initialHealthSnapshot: { Self.healthSnapshot() },
            preparePreflight: { _ in preflight },
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base"),
            prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff: { _ in
                executedSteps.append(.stopRuntimeServices)
            },
            stopRuntimeServices: {
                executedSteps.append(.stopRuntimeServices)
            },
            createDirectory: { _, _ in },
            fileSize: { _ in 1 },
            replaceFile: { _, _ in
                executedSteps.append(.replaceRootfsBase)
            },
            replaceUpdateArtifacts: { _, _ in
                executedSteps.append(.replaceUpdateArtifacts)
                throw RuntimeChaosError.applyArtifactWriteDenied
            },
            runMigrations: { _, _ in
                executedSteps.append(.runMigrations)
            },
            refreshCloudInitSeedIfNeeded: { _ in
                executedSteps.append(.refreshCloudInitSeed)
            },
            writeRuntimeVersion: { _, _ in
                executedSteps.append(.writeRuntimeVersion)
            },
            startRuntimeServices: { policy in
                restartedPolicy = policy
                if rollbackBackup == nil {
                    executedSteps.append(.startRuntimeServices)
                }
            },
            activateGuestUpdateIfNeeded: { _ in
                executedSteps.append(.activateGuestUpdate)
            },
            waitForHealth: { _ in
                executedSteps.append(.waitRuntimeHealth)
            },
            rollback: { backup in
                rollbackBackup = backup
                throw RuntimeChaosError.rollbackRestoreDenied
            },
            writeStatus: { level, operation, message in
                statuses.append((level, operation, message))
            },
            writeBestEffortStatus: { level, operation, message in
                statuses.append((level, operation, message))
            },
            publishProgress: { event in
                progressEvents.append(event)
            },
            pruneOldRuntimeArtifacts: {},
            describeError: RuntimeErrorDescription.describe,
            log: { message in
                logs.append(message)
            }
        )

        XCTAssertThrowsError(try RuntimeApplyBundleWorkflow().run(
            input: ApplyRuntimeBundleInput(bundleURL: URL(fileURLWithPath: "/incoming/update-bundle")),
            operations: operations
        )) { error in
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
        var effects: [String] = []
        let useCase = RollbackRuntimeWorkflow()
        let context = RollbackRuntimeExecutionContext(
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/runtime/runtime-version.json"),
            vmDisk: URL(fileURLWithPath: "/product/vm/vm-disk.img"),
            managerAppPath: URL(fileURLWithPath: "/Applications/VitalServer Manager.app"),
            nginxDirectory: URL(fileURLWithPath: "/product/nginx"),
            deployDirectory: URL(fileURLWithPath: "/product/deploy")
        )
        let operations = RollbackRuntimeOperations(
            resolveBackupSelection: { _ in preflight.backup },
            observeBackupDirectory: { backup in
                RollbackRuntimeBackupDirectoryObservation(backup: backup, backupDirectoryState: .directory)
            },
            loadBackupManifest: { _ in
                BackupManifest(
                    product: Constants.Product.identifier,
                    createdAt: "2026-05-31T00:00:00Z",
                    reason: "before-1.2.3",
                    rootfsBase: Constants.Artifacts.rootfsBase,
                    vmDisk: Constants.BootAssets.disk,
                    vmDiskPreserved: true
                )
            },
            observeBackupRootfs: { plan in
                RollbackRuntimeBackupRootfsObservation(backupPlan: plan, backupRootfsState: .file)
            },
            serviceRestartPolicy: { preflight.restartPolicy },
            observeStepRequiredInput: { _, _, requiredInput in
                RollbackRuntimeStepRequiredInputObservation(
                    requiredInput: requiredInput,
                    backupVersionState: .file
                )
            },
            stopRuntimeServices: {
                effects.append("stop")
            },
            replaceFile: { source, destination in
                effects.append("replace:\(source.lastPathComponent):\(destination.lastPathComponent)")
                if destination == context.rootfsBase {
                    throw RuntimeChaosError.rollbackRestoreDenied
                }
            },
            writeRuntimeVersion: { _, _ in
                XCTFail("rootfs restore failure should stop before runtime version restore")
            },
            restoreBackupPathIfExists: { _, _ in
                XCTFail("rootfs restore failure should stop before artifact restore")
            },
            restoreRuntimeToolsIfExists: { _ in
                XCTFail("rootfs restore failure should stop before runtime tools restore")
            },
            startRuntimeServices: { _ in
                XCTFail("rootfs restore failure should stop before service start")
            },
            waitForHealth: { _ in
                XCTFail("rootfs restore failure should stop before health wait")
            },
            writeStatus: { level, operation, message in
                statuses.append((level, operation, message))
            },
            writeProgress: { event in
                progressEvents.append(event)
            },
            describeError: { _ in "progress write failed" },
            log: { _ in }
        )

        XCTAssertThrowsError(try useCase.run(.specificBackup(preflight.backup), context: context, operations: operations)) { error in
            XCTAssertEqual(String(describing: error), "rollbackRestoreDenied")
        }

        XCTAssertEqual(effects, ["stop", "replace:rootfs-base.raw.gz:rootfs-base.raw.gz"])
        XCTAssertEqual(progressEvents.last?.step, .rollbackRestoreRootfsBase)
        XCTAssertEqual(progressEvents.last?.stepStatus, .failed)
        XCTAssertEqual(statuses.last?.level, .recovering)
        XCTAssertEqual(statuses.last?.operation, .rollback)
    }

    func testRollbackPreflightChaosStopsWhenRestoreArtifactIsMissing() {
        let backup = URL(fileURLWithPath: "/product/backups/20260531T000000Z-before-1.2.3")
        let missingRootfs = backup.appendingPathComponent(Constants.Artifacts.rootfsBase)
        let operations = RollbackRuntimeOperations(
            resolveBackupSelection: { selection in
                switch selection {
                case .specificBackup(let selectedBackup):
                    return selectedBackup
                case .latestBackup:
                    XCTFail("specific backup should not resolve latest backup")
                    return URL(fileURLWithPath: "/unused")
                }
            },
            observeBackupDirectory: { selectedBackup in
                RollbackRuntimeBackupDirectoryObservation(
                    backup: selectedBackup,
                    backupDirectoryState: selectedBackup == backup ? .directory : .missing
                )
            },
            loadBackupManifest: { _ in
                BackupManifest(
                    product: Constants.Product.identifier,
                    createdAt: "2026-05-31T00:00:00Z",
                    reason: "before-1.2.3",
                    rootfsBase: Constants.Artifacts.rootfsBase,
                    vmDisk: Constants.BootAssets.disk,
                    vmDiskPreserved: true
                )
            },
            observeBackupRootfs: { plan in
                RollbackRuntimeBackupRootfsObservation(backupPlan: plan, backupRootfsState: .missing)
            },
            serviceRestartPolicy: {
                XCTFail("missing restore artifact should stop before service policy")
                return RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
            },
            observeStepRequiredInput: { _, _, requiredInput in
                RollbackRuntimeStepRequiredInputObservation(requiredInput: requiredInput, backupVersionState: .missing)
            },
            stopRuntimeServices: { XCTFail("missing restore artifact should stop before step execution") },
            replaceFile: { _, _ in XCTFail("missing restore artifact should stop before step execution") },
            writeRuntimeVersion: { _, _ in XCTFail("missing restore artifact should stop before step execution") },
            restoreBackupPathIfExists: { _, _ in XCTFail("missing restore artifact should stop before step execution") },
            restoreRuntimeToolsIfExists: { _ in XCTFail("missing restore artifact should stop before step execution") },
            startRuntimeServices: { _ in XCTFail("missing restore artifact should stop before step execution") },
            waitForHealth: { _ in XCTFail("missing restore artifact should stop before step execution") },
            writeStatus: { _, _, _ in },
            writeProgress: { _ in },
            describeError: { _ in "progress write failed" },
            log: { _ in XCTFail("missing restore artifact should stop before logging") }
        )

        XCTAssertThrowsError(try RollbackRuntimeWorkflow().preparePreflight(.specificBackup(backup), operations: operations)) { error in
            XCTAssertEqual(String(describing: error), "missing file: \(missingRootfs.path)")
        }
    }

    func testBackupChaosStopsBeforeManifestWhenManagedArtifactCopyIsDenied() {
        let paths = backupStorePaths()
        var createdDirectories: [URL] = []
        var wroteManifest = false
        let store = RuntimeBackupStore(
            paths: paths,
            metadata: RuntimeBackupStoreMetadata(
                productIdentifier: "ai.tirosh.vitalserver.helper",
                rootfsBaseName: "rootfs-base.raw.gz",
                runtimeVersionName: "runtime-version.json",
                backupManifestName: "backup-manifest.json",
                vmDiskName: "vm-disk.img",
                runtimeToolPaths: [
                    URL(fileURLWithPath: Constants.InstallPaths.vmBin),
                    URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
                    URL(fileURLWithPath: Constants.InstallPaths.uninstall),
                ]
            ),
            timestamp: { "20260531T000000Z" },
            isoTimestamp: { "2026-05-31T00:00:00Z" },
            pathState: { url in url == paths.rootfsBase ? .file : .missing },
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
    ) -> RuntimeBundleComposition {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        return RuntimeBundleComposition(
            context: RuntimeBundleCompositionContext(
                installedPaths: installedPaths,
                bundlesDirectory: URL(fileURLWithPath: "/product/bundles"),
                backupsDirectory: URL(fileURLWithPath: "/product/backups"),
                logsDirectory: URL(fileURLWithPath: "/product/logs"),
                rootfsBase: URL(fileURLWithPath: "/product/rootfs-base.raw.gz"),
                vmDisk: URL(fileURLWithPath: "/product/vm-disk.img")
            ),
            operations: RuntimeBundleCompositionOperations(
                fileStore: fileStore,
                runtimeHealthSnapshot: { Self.healthSnapshot() },
                rotateRuntimeLogs: {},
                rollback: { _ in },
                startRuntimeServices: { _ in },
                stopRuntimeServices: {},
                prepareGuestShutdownAndStopRuntimeServicesAfterPoweroff: { _ in },
                isLaunchdLoaded: { _ in false },
                createBackup: { _ in URL(fileURLWithPath: "/product/backups/backup") },
                statusReporter: RuntimeWorkflowStatusReporter(
                    writeStatus: { _, _, _ in },
                    writeProgress: { _ in },
                    describeError: { _ in "unexpected" },
                    log: log
                ),
                pruneOldRuntimeArtifacts: {},
                materializeBundle: { url in
                    guard fileStore.directoryExists(url) else {
                        throw LauncherError.missingFile(url.path)
                    }
                    return RuntimeMaterializedBundle(bundleURL: url, temporaryRoot: nil)
                },
                executeMaterializationCleanupPlan: { _ in },
                removeMaterializedBundleTemporaryRoot: { _ in },
                stageMaterializedBundle: { input in
                    try RuntimeBundleStager(
                        context: RuntimeBundleStagingContext(
                            bundlesDirectory: URL(fileURLWithPath: "/product/bundles"),
                            updateFreeSpaceMarginBytes: Constants.Runtime.updateFreeSpaceMarginBytes
                        ),
                        operations: RuntimeBundleStagingOperations(
                            directorySize: { url in
                                try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
                            },
                            compressedSourceSize: { url in
                                fileStore.fileExists(url) ? try fileStore.fileSize(url) : 0
                            },
                            destinationState: { url in
                                fileStore.pathState(at: url)
                            },
                            createDirectory: { url, withIntermediateDirectories in
                                try fileStore.createDirectory(
                                    at: url,
                                    withIntermediateDirectories: withIntermediateDirectories
                                )
                            },
                            removeItem: { url in
                                try fileStore.removeItem(at: url)
                            },
                            copyItem: { source, destination in
                                try fileStore.copyItem(at: source, to: destination)
                            },
                            requireFreeSpace: { _, _, _ in },
                            log: log
                        )
                    ).stage(input: input)
                },
                validateUpdateArtifactPayload: { _, _ in },
                replaceUpdateArtifacts: { _, _ in },
                runMigrations: { _, _ in },
                requireFreeSpace: { _, _, _ in },
                directorySize: { url in
                    try fileStore.recursiveRegularFileSize(at: url, skipsHiddenFiles: true)
                },
                replaceFile: { _, _ in },
                writeRuntimeVersion: { _, _ in },
                refreshCloudInitSeedIfNeeded: { _ in },
                activateGuestUpdateIfNeeded: { _ in },
                waitForHealth: { _ in },
                requireGuestCapability: { _ in },
                acquireOperationLease: { operation in
                    RuntimeOperationLeaseDocument(
                        operationId: UUID().uuidString,
                        operation: operation,
                        ownerPID: 123,
                        startedAt: "2026-05-22T00:00:00Z",
                        heartbeatAt: "2026-05-22T00:00:00Z",
                        expiresAt: nil,
                        message: nil
                    )
                },
                heartbeatOperationLease: { _ in },
                releaseOperationLease: { _ in },
                log: log
            )
        )
    }

    private static func healthSnapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            vmExecutable: .executable,
            proxyExecutable: .executable,
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
        artifacts: [UpdateBundleArtifact] = [],
        requiresGuestActivation: Bool = false
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: Constants.Product.identifier,
            helperVersion: version,
            releaseLabel: version,
            targetPlatform: "macos-arm64",
            components: ["updater": version],
            requiresGuestActivation: requiresGuestActivation,
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
            vmExecutable: .executable,
            proxyExecutable: .executable,
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

private final class RuntimeUpdateChaosGuestControlGateway: RuntimeGuestControlGateway {
    let result: RuntimeGuestCapabilityReadResult

    init(result: RuntimeGuestCapabilityReadResult) {
        self.result = result
    }

    func capabilities() throws -> RuntimeGuestControlCapabilities {
        switch result {
        case .loaded(let capabilities):
            return capabilities
        case .failed(let message):
            throw RuntimeUpdateChaosGuestControlGatewayError(message)
        }
    }

    func listServices() throws -> RuntimeGuestControlServiceList {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected listServices")
    }

    func stackStatus() throws -> RuntimeGuestControlStackStatus {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected stackStatus")
    }

    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected serviceStatus \(service)")
    }

    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected startService \(service)")
    }

    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected stopService \(service)")
    }

    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected restartService \(service)")
    }

    func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected reconcileServices")
    }

    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected operation \(operationId)")
    }

    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        throw RuntimeUpdateChaosGuestControlGatewayError("unexpected latestVitalDBObservation")
    }
}

private struct RuntimeUpdateChaosGuestControlGatewayError: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
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
