import Foundation
import Application
import Contracts
import Domain
import Workflow
import XCTest
import Errors

final class RuntimeApplyBundlePreflightRunnerTests: XCTestCase {
    func testPrepareBuildsPreflightContextInOrder() throws {
        let inputBundle = URL(fileURLWithPath: "/incoming/bundle")
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let backupsDirectory = URL(fileURLWithPath: "/product/backups")
        let rootfsBase = URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        let stagedRootfs = stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase)
        let backup = URL(fileURLWithPath: "/product/backups/backup-before-1.2.3")
        var events: [String] = []
        var requiredSpace: (url: URL, bytes: UInt64, operation: RuntimeOperation)?

        let runner = RuntimeApplyBundlePreflightRunner(
            stageBundle: { url in
                events.append("stage:\(url.path)")
                return stagedBundle
            },
            loadStagedManifest: { url in
                events.append("manifest:\(url.lastPathComponent)")
                return self.manifest(
                    version: "1.2.3",
                    artifacts: [
                        UpdateBundleArtifact(
                            name: RuntimeFileNames.rootfsBase,
                            type: .rootfsBase,
                            sha256: "abc",
                            size: 20
                        ),
                    ]
                )
            },
            resolveRootfsStorage: { plan in
                try resolveRootfsStorage(plan) { observedStagedRootfs, observedRootfsBase in
                    XCTAssertEqual(observedStagedRootfs, stagedRootfs)
                    XCTAssertEqual(observedRootfsBase, rootfsBase)
                    return ApplyRuntimeBundleRootfsStorageObservation(
                        stagedRootfs: stagedRootfs,
                        stagedRootfsExists: true,
                        installedRootfsBytes: 10,
                        incomingRootfsBytes: 20
                    )
                }
            },
            createDirectory: { url, withIntermediateDirectories in
                events.append("mkdir:\(url.path):\(withIntermediateDirectories)")
            },
            requireFreeSpace: { url, bytes, operation in
                requiredSpace = (url, bytes, operation)
            },
            checkCompatibility: { manifest in
                events.append("compatibility:\(manifest.version)")
            },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: true)
            },
            executeCapabilityInstruction: { instruction in
                try executeCapabilityInstruction(
                    instruction,
                    healthSnapshot: { healthySnapshot() },
                    requireGuestCapability: { capability in
                        events.append("capability:\(capability.rawValue)")
                    }
                )
            },
            createBackup: { reason in
                events.append("backup:\(reason)")
                return backup
            },
            directorySize: { url in
                events.append("du:\(url.path)")
                return 30
            },
            updateFreeSpaceMarginBytes: updateFreeSpaceMarginBytes,
            log: { _ in }
        )

        let context = try runner.prepare(
            bundleURL: inputBundle,
            backupsDirectory: backupsDirectory,
            rootfsBase: rootfsBase
        )

        XCTAssertEqual(context.stagedBundle, stagedBundle)
        XCTAssertEqual(context.manifest.version, "1.2.3")
        XCTAssertEqual(context.stagedRootfs, stagedRootfs)
        XCTAssertEqual(context.backup, backup)
        XCTAssertEqual(context.restartPolicy, RuntimeServiceRestartPolicy(
            restartVM: true,
            restartGuestLogSync: true,
            restartProxy: false,
            restartWatchdog: true
        ))
        XCTAssertEqual(requiredSpace?.url, backupsDirectory)
        XCTAssertEqual(requiredSpace?.bytes, 60 + updateFreeSpaceMarginBytes)
        XCTAssertEqual(requiredSpace?.operation, .applyBundle)
        XCTAssertEqual(events, [
            "stage:/incoming/bundle",
            "manifest:update-bundle-1.2.3",
            "compatibility:1.2.3",
            "du:/managed/update-bundle-1.2.3",
            "mkdir:/product/backups:true",
            "policy",
            "capability:prepare-update-shutdown",
            "backup:before-1.2.3",
            "du:/product/backups/backup-before-1.2.3",
        ])
    }

    func testPrepareSkipsRootfsPreflightWhenBundleDoesNotIncludeRootfs() throws {
        let inputBundle = URL(fileURLWithPath: "/incoming/bundle")
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let backupsDirectory = URL(fileURLWithPath: "/product/backups")
        let backup = URL(fileURLWithPath: "/product/backups/backup-before-1.2.3")
        var requiredSpace: UInt64?

        let runner = RuntimeApplyBundlePreflightRunner(
            stageBundle: { _ in stagedBundle },
            loadStagedManifest: { _ in self.manifest(version: "1.2.3") },
            resolveRootfsStorage: { plan in
                try resolveRootfsStorage(plan) { _, _ in
                    XCTFail("rootfs storage should not be observed")
                    return ApplyRuntimeBundleRootfsStorageObservation(
                        stagedRootfs: URL(fileURLWithPath: "/unused"),
                        stagedRootfsExists: false,
                        installedRootfsBytes: nil,
                        incomingRootfsBytes: nil
                    )
                }
            },
            createDirectory: { _, _ in },
            requireFreeSpace: { _, bytes, _ in requiredSpace = bytes },
            checkCompatibility: { _ in },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: true, restartWatchdog: false)
            },
            executeCapabilityInstruction: { instruction in
                try executeCapabilityInstruction(
                    instruction,
                    healthSnapshot: {
                        XCTFail("runtime health should not be checked when VM is not running")
                        return healthySnapshot()
                    },
                    requireGuestCapability: { _ in
                        XCTFail("guest capability should not be required")
                    }
                )
            },
            createBackup: { _ in backup },
            directorySize: { _ in 10 },
            updateFreeSpaceMarginBytes: updateFreeSpaceMarginBytes,
            log: { _ in }
        )

        let context = try runner.prepare(
            bundleURL: inputBundle,
            backupsDirectory: backupsDirectory,
            rootfsBase: URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        )

        XCTAssertNil(context.stagedRootfs)
        XCTAssertFalse(context.updatesRootfsBase)
        XCTAssertEqual(requiredSpace, 10 + updateFreeSpaceMarginBytes)
    }

    func testPrepareFailsWhenStagedRootfsIsMissing() {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let runner = RuntimeApplyBundlePreflightRunner(
            stageBundle: { _ in stagedBundle },
            loadStagedManifest: { _ in
                self.manifest(
                    version: "1.2.3",
                    artifacts: [
                        UpdateBundleArtifact(
                            name: RuntimeFileNames.rootfsBase,
                            type: .rootfsBase,
                            sha256: "abc",
                            size: 20
                        ),
                    ]
                )
            },
            resolveRootfsStorage: { plan in
                try resolveRootfsStorage(plan) { stagedRootfs, _ in
                    ApplyRuntimeBundleRootfsStorageObservation(
                        stagedRootfs: stagedRootfs,
                        stagedRootfsExists: false,
                        installedRootfsBytes: nil,
                        incomingRootfsBytes: nil
                    )
                }
            },
            createDirectory: { _, _ in XCTFail("should not create backup directory") },
            requireFreeSpace: { _, _, _ in },
            checkCompatibility: { _ in },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
            },
            executeCapabilityInstruction: { instruction in
                try executeCapabilityInstruction(
                    instruction,
                    healthSnapshot: {
                        XCTFail("runtime health should not be checked after missing rootfs")
                        return healthySnapshot()
                    },
                    requireGuestCapability: { _ in }
                )
            },
            createBackup: { _ in URL(fileURLWithPath: "/backup") },
            directorySize: { _ in 0 },
            updateFreeSpaceMarginBytes: updateFreeSpaceMarginBytes,
            log: { _ in }
        )

        XCTAssertThrowsError(try runner.prepare(
            bundleURL: URL(fileURLWithPath: "/incoming/bundle"),
            backupsDirectory: URL(fileURLWithPath: "/product/backups"),
            rootfsBase: URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "missing file: \(stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase).path)"
            )
        }
    }

    func testPreparePropagatesRootfsSizeReadFailureBeforeFreeSpaceCheck() {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let stagedRootfs = stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase)
        let rootfsBase = URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        let runner = RuntimeApplyBundlePreflightRunner(
            stageBundle: { _ in stagedBundle },
            loadStagedManifest: { _ in
                self.manifest(
                    version: "1.2.3",
                    artifacts: [
                        UpdateBundleArtifact(
                            name: RuntimeFileNames.rootfsBase,
                            type: .rootfsBase,
                            sha256: "abc",
                            size: 20
                        ),
                    ]
                )
            },
            resolveRootfsStorage: { plan in
                try resolveRootfsStorage(plan) { observedStagedRootfs, observedRootfsBase in
                    XCTAssertEqual(observedStagedRootfs, stagedRootfs)
                    XCTAssertEqual(observedRootfsBase, rootfsBase)
                    throw RuntimeApplyBundleWorkflowError.operationFailed("missing file: \(rootfsBase.path)")
                }
            },
            createDirectory: { _, _ in XCTFail("should not create backup directory") },
            requireFreeSpace: { _, _, _ in XCTFail("should not check free space") },
            checkCompatibility: { _ in },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
            },
            executeCapabilityInstruction: { instruction in
                try executeCapabilityInstruction(
                    instruction,
                    healthSnapshot: {
                        XCTFail("runtime health should not be checked after rootfs size read failure")
                        return healthySnapshot()
                    },
                    requireGuestCapability: { _ in }
                )
            },
            createBackup: { _ in URL(fileURLWithPath: "/backup") },
            directorySize: { _ in 30 },
            updateFreeSpaceMarginBytes: updateFreeSpaceMarginBytes,
            log: { _ in }
        )

        XCTAssertThrowsError(try runner.prepare(
            bundleURL: URL(fileURLWithPath: "/incoming/bundle"),
            backupsDirectory: URL(fileURLWithPath: "/product/backups"),
            rootfsBase: rootfsBase
        )) { error in
            XCTAssertEqual(String(describing: error), "missing file: \(rootfsBase.path)")
        }
    }

    func testPrepareRequiresGuestCapabilitiesBeforeCreatingBackup() {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        var events: [String] = []
        let runner = RuntimeApplyBundlePreflightRunner(
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
                    ]
                )
            },
            resolveRootfsStorage: { plan in
                try resolveRootfsStorage(plan) { stagedRootfs, _ in
                    ApplyRuntimeBundleRootfsStorageObservation(
                        stagedRootfs: stagedRootfs,
                        stagedRootfsExists: false,
                        installedRootfsBytes: nil,
                        incomingRootfsBytes: nil
                    )
                }
            },
            createDirectory: { _, _ in events.append("mkdir") },
            requireFreeSpace: { _, _, _ in },
            checkCompatibility: { _ in },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: false)
            },
            executeCapabilityInstruction: { instruction in
                try executeCapabilityInstruction(
                    instruction,
                    healthSnapshot: { healthySnapshot() },
                    requireGuestCapability: { capability in
                        events.append("capability:\(capability.rawValue)")
                        if capability == .activateUpdate {
                            throw RuntimeApplyBundleWorkflowError.operationFailed("guest capability missing: \(capability.rawValue)")
                        }
                    }
                )
            },
            createBackup: { _ in
                events.append("backup")
                return URL(fileURLWithPath: "/backup")
            },
            directorySize: { _ in 10 },
            updateFreeSpaceMarginBytes: updateFreeSpaceMarginBytes,
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
            "mkdir",
            "capability:prepare-update-shutdown",
            "capability:activate-update",
        ])
    }

    func testPrepareBlocksUpdateWhenGuestStorageHealthRequiresVMDiskRepair() {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        var events: [String] = []
        let runner = RuntimeApplyBundlePreflightRunner(
            stageBundle: { _ in stagedBundle },
            loadStagedManifest: { _ in self.manifest(version: "1.2.3") },
            resolveRootfsStorage: { plan in
                try resolveRootfsStorage(plan) { _, _ in
                    XCTFail("rootfs storage should not be observed")
                    return ApplyRuntimeBundleRootfsStorageObservation(
                        stagedRootfs: URL(fileURLWithPath: "/unused"),
                        stagedRootfsExists: false,
                        installedRootfsBytes: nil,
                        incomingRootfsBytes: nil
                    )
                }
            },
            createDirectory: { _, _ in events.append("mkdir") },
            requireFreeSpace: { _, _, _ in events.append("space") },
            checkCompatibility: { _ in events.append("compatibility") },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: false)
            },
            executeCapabilityInstruction: { instruction in
                try executeCapabilityInstruction(
                    instruction,
                    healthSnapshot: {
                        events.append("health")
                        return healthySnapshot(vmErrors: [.guestFilesystemError])
                    },
                    requireGuestCapability: { capability in
                        events.append("capability:\(capability.rawValue)")
                    },
                    log: { message in events.append("log:\(message)") }
                )
            },
            createBackup: { reason in
                events.append("backup:\(reason)")
                return URL(fileURLWithPath: "/backup")
            },
            directorySize: { _ in 10 },
            updateFreeSpaceMarginBytes: updateFreeSpaceMarginBytes,
            log: { message in events.append("log:\(message)") }
        )

        XCTAssertThrowsError(try runner.prepare(
            bundleURL: URL(fileURLWithPath: "/incoming/bundle"),
            backupsDirectory: URL(fileURLWithPath: "/product/backups"),
            rootfsBase: URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "VM disk health blocks update; run Repair VM Disk before applying update. errors=vm-guest-filesystem-error"
            )
        }
        XCTAssertEqual(events, [
            "log:bundle apply manifest version=1.2.3 runtimeVersion=1.2.3 artifacts=0 migrations=0",
            "compatibility",
            "log:bundle apply storage preflight stagedBundle=0.0 MiB",
            "log:bundle apply storage preflight rootfsBase=unchanged",
            "mkdir",
            "space",
            "policy",
            "log:runtime services before update vm=loaded guestLogSync=loaded proxy=not-loaded watchdog=not-loaded",
            "health",
            "log:bundle apply blocked by VM guest storage health errors=vm-guest-filesystem-error",
        ])
    }

    private func manifest(
        version: String,
        artifacts: [UpdateBundleArtifact] = []
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: version,
            releaseLabel: version,
            targetPlatform: "macos-arm64",
            components: ["updater": version],
            requiresGuestActivation: false,
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts,
            migrations: []
        )
    }
}

private let updateFreeSpaceMarginBytes: UInt64 = 2 * 1024 * 1024 * 1024

private func resolveRootfsStorage(
    _ plan: ApplyRuntimeBundleRootfsStorageObservationPlan,
    observe: (URL, URL) throws -> ApplyRuntimeBundleRootfsStorageObservation
) throws -> ApplyRuntimeBundleRootfsStoragePreflightPlan {
    let decision: ApplyRuntimeBundleRootfsStorageDecision
    switch plan {
    case .unchanged(let rootfsStoragePlan):
        decision = .planned(rootfsStoragePlan)
    case .replacing(let stagedRootfs, let rootfsBase):
        decision = UpdateRuntimeUseCase().rootfsStorageDecision(
            observation: try observe(stagedRootfs, rootfsBase)
        )
    }
    switch decision {
    case .planned(let rootfsStoragePlan):
        return rootfsStoragePlan
    case .failed(let message):
        throw RuntimeApplyBundleWorkflowError.operationFailed(message)
    }
}

private func executeCapabilityInstruction(
    _ instruction: ApplyRuntimeBundlePreflightCapabilityInstruction,
    healthSnapshot: () -> RuntimeHealthSnapshot,
    requireGuestCapability: (RuntimeGuestCapabilityRequirement) throws -> Void,
    log: (String) -> Void = { _ in }
) throws {
    switch instruction {
    case .requireRuntimeDiskHealthAllowsUpdate:
        switch UpdateRuntimeUseCase().diskHealthDecision(snapshot: healthSnapshot()) {
        case .allowed:
            return
        case .blocked(_, let logMessage, let failureMessage):
            log(logMessage)
            throw RuntimeApplyBundleWorkflowError.operationFailed(failureMessage)
        }
    case .requireGuestCapability(let capability):
        try requireGuestCapability(capability)
    }
}

private func healthySnapshot(vmErrors: [RuntimeVMError] = []) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: true,
        proxyExecutable: true,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmState: vmErrors.isEmpty ? .running : .failed,
        vmErrors: vmErrors,
        vmIP: "192.168.64.2",
        proxyPort: 80,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        failureReasons: vmErrors.map(RuntimeFailureReason.init(vmError:))
    )
}
