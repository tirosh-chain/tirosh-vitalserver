import Foundation
import Application
import Contracts
import Domain
import XCTest
import Errors

final class ApplyRuntimeBundlePreflightUseCaseTests: XCTestCase {
    func testPrepareBuildsPreflightContextFromExplicitPortsInOrder() throws {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let stagedRootfs = stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase)
        let rootfsBase = URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        let backup = URL(fileURLWithPath: "/product/backups/backup-before-1.2.3")
        var events: [String] = []
        var requiredSpace: (url: URL, bytes: UInt64, operation: RuntimeOperation)?

        let operations = operations(
            stagedBundle: stagedBundle,
            manifest: manifest(
                version: "1.2.3",
                artifacts: [
                    UpdateBundleArtifact(
                        name: RuntimeFileNames.rootfsBase,
                        type: .rootfsBase,
                        sha256: "abc",
                        size: 20
                    ),
                ]
            ),
            observeRootfsStorage: { observedStagedRootfs, observedRootfsBase in
                events.append("observe-rootfs:\(observedStagedRootfs.lastPathComponent)")
                XCTAssertEqual(observedStagedRootfs, stagedRootfs)
                XCTAssertEqual(observedRootfsBase, rootfsBase)
                return ApplyRuntimeBundleRootfsStorageObservation(
                    stagedRootfs: stagedRootfs,
                    stagedRootfsExists: true,
                    installedRootfsBytes: 10,
                    incomingRootfsBytes: 20
                )
            },
            createDirectory: { url, withIntermediateDirectories in
                events.append("mkdir:\(url.path):\(withIntermediateDirectories)")
            },
            requireFreeSpace: { url, bytes, operation in
                events.append("space")
                requiredSpace = (url, bytes, operation)
            },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(
                    restartVM: true,
                    restartGuestLogSync: true,
                    restartProxy: false,
                    restartWatchdog: true
                )
            },
            requireGuestCapability: { capability in
                events.append("capability:\(capability.rawValue)")
            },
            createBackup: { reason in
                events.append("backup:\(reason)")
                return backup
            },
            directorySize: { url in
                events.append("du:\(url.path)")
                return url == backup ? 40 : 30
            },
            event: { events.append($0) },
            log: { _ in }
        )

        let context = try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: input(rootfsBase: rootfsBase),
            operations: operations
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
        XCTAssertEqual(requiredSpace?.url, URL(fileURLWithPath: "/product/backups"))
        XCTAssertEqual(requiredSpace?.bytes, 60 + updateFreeSpaceMarginBytes)
        XCTAssertEqual(requiredSpace?.operation, .applyBundle)
        XCTAssertEqual(events, [
            "stage:/incoming/bundle",
            "manifest:update-bundle-1.2.3",
            "du:/managed/update-bundle-1.2.3",
            "observe-rootfs:rootfs-base.raw.gz",
            "mkdir:/product/backups:true",
            "space",
            "policy",
            "health",
            "capability:prepare-update-shutdown",
            "backup:before-1.2.3",
            "du:/product/backups/backup-before-1.2.3",
        ])
    }

    func testPrepareRejectsIncompatibleManifestBeforeReadingStorageOrCreatingBackup() {
        var events: [String] = []
        let operations = operations(
            manifest: manifest(version: "2.0.0", minUpdaterVersion: "9.0.0"),
            observeRootfsStorage: { _, _ in
                XCTFail("rootfs storage should not be observed after compatibility failure")
                return missingRootfsObservation()
            },
            createDirectory: { _, _ in events.append("mkdir") },
            requireFreeSpace: { _, _, _ in events.append("space") },
            serviceRestartPolicy: {
                events.append("policy")
                return stoppedPolicy()
            },
            createBackup: { _ in
                events.append("backup")
                return URL(fileURLWithPath: "/backup")
            },
            directorySize: { url in
                events.append("du:\(url.path)")
                return 1
            },
            event: { events.append($0) },
            log: { message in events.append("log:\(message)") }
        )

        XCTAssertThrowsError(try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: input(currentUpdaterVersion: "1.0.0"),
            operations: operations
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "update bundle requires updater 9.0.0 or newer; current updater is 1.0.0"
            )
        }

        XCTAssertEqual(events, [
            "stage:/incoming/bundle",
            "manifest:update-bundle-1.2.3",
            "log:bundle apply manifest version=2.0.0 runtimeVersion=2.0.0 artifacts=0 migrations=0",
        ])
    }

    func testPrepareSkipsRootfsObservationWhenBundleDoesNotIncludeRootfs() throws {
        var requiredSpace: UInt64?
        let operations = operations(
            manifest: manifest(version: "1.2.3"),
            observeRootfsStorage: { _, _ in
                XCTFail("rootfs storage should not be observed")
                return missingRootfsObservation()
            },
            requireFreeSpace: { _, bytes, _ in requiredSpace = bytes },
            serviceRestartPolicy: { RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: true, restartWatchdog: false) },
            runtimeHealthSnapshot: {
                XCTFail("runtime health should not be checked when VM is not running")
                return healthySnapshot()
            },
            requireGuestCapability: { _ in XCTFail("guest capability should not be required") },
            directorySize: { _ in 10 }
        )

        let context = try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: input(),
            operations: operations
        )

        XCTAssertNil(context.stagedRootfs)
        XCTAssertFalse(context.updatesRootfsBase)
        XCTAssertEqual(requiredSpace, 10 + updateFreeSpaceMarginBytes)
    }

    func testPrepareFailsWhenStagedRootfsIsExplicitlyMissing() {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let operations = operations(
            stagedBundle: stagedBundle,
            manifest: manifest(
                version: "1.2.3",
                artifacts: [
                    UpdateBundleArtifact(
                        name: RuntimeFileNames.rootfsBase,
                        type: .rootfsBase,
                        sha256: "abc",
                        size: 20
                    ),
                ]
            ),
            observeRootfsStorage: { stagedRootfs, _ in
                ApplyRuntimeBundleRootfsStorageObservation(
                    stagedRootfs: stagedRootfs,
                    stagedRootfsExists: false,
                    installedRootfsBytes: nil,
                    incomingRootfsBytes: nil
                )
            },
            createDirectory: { _, _ in XCTFail("should not create backup directory") },
            requireFreeSpace: { _, _, _ in XCTFail("should not check free space") }
        )

        XCTAssertThrowsError(try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: input(),
            operations: operations
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "missing file: \(stagedBundle.appendingPathComponent(RuntimeFileNames.rootfsBase).path)"
            )
        }
    }

    func testPreparePropagatesRootfsSizeReadFailureBeforeFreeSpaceCheck() {
        let rootfsBase = URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        let operations = operations(
            manifest: manifest(
                version: "1.2.3",
                artifacts: [
                    UpdateBundleArtifact(
                        name: RuntimeFileNames.rootfsBase,
                        type: .rootfsBase,
                        sha256: "abc",
                        size: 20
                    ),
                ]
            ),
            observeRootfsStorage: { _, observedRootfsBase in
                XCTAssertEqual(observedRootfsBase, rootfsBase)
                throw TestError.operationFailed("missing file: \(rootfsBase.path)")
            },
            createDirectory: { _, _ in XCTFail("should not create backup directory") },
            requireFreeSpace: { _, _, _ in XCTFail("should not check free space") }
        )

        XCTAssertThrowsError(try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: input(rootfsBase: rootfsBase),
            operations: operations
        )) { error in
            XCTAssertEqual(String(describing: error), "missing file: \(rootfsBase.path)")
        }
    }

    func testPrepareRequiresGuestCapabilitiesBeforeCreatingBackup() {
        var events: [String] = []
        let operations = operations(
            manifest: manifest(
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
            ),
            createDirectory: { _, _ in events.append("mkdir") },
            requireFreeSpace: { _, _, _ in },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: false)
            },
            requireGuestCapability: { capability in
                events.append("capability:\(capability.rawValue)")
                if capability == .activateUpdate {
                    throw TestError.operationFailed("guest capability missing: \(capability.rawValue)")
                }
            },
            createBackup: { _ in
                events.append("backup")
                return URL(fileURLWithPath: "/backup")
            }
        )

        XCTAssertThrowsError(try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: input(),
            operations: operations
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
        var events: [String] = []
        let operations = operations(
            manifest: manifest(version: "1.2.3"),
            createDirectory: { _, _ in events.append("mkdir") },
            requireFreeSpace: { _, _, _ in events.append("space") },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartGuestLogSync: true, restartProxy: false, restartWatchdog: false)
            },
            runtimeHealthSnapshot: {
                return healthySnapshot(vmErrors: [.guestFilesystemError])
            },
            requireGuestCapability: { capability in
                events.append("capability:\(capability.rawValue)")
            },
            createBackup: { reason in
                events.append("backup:\(reason)")
                return URL(fileURLWithPath: "/backup")
            },
            directorySize: { _ in 10 },
            event: { events.append($0) },
            log: { message in events.append("log:\(message)") }
        )

        XCTAssertThrowsError(try ApplyRuntimeBundlePreflightUseCase().prepare(
            input: input(),
            operations: operations
        )) { error in
            XCTAssertEqual(
                String(describing: error),
                "VM disk health blocks update; run Repair VM Disk before applying update. errors=vm-guest-filesystem-error"
            )
        }

        XCTAssertEqual(events, [
            "stage:/incoming/bundle",
            "manifest:update-bundle-1.2.3",
            "log:bundle apply manifest version=1.2.3 runtimeVersion=1.2.3 artifacts=0 migrations=0",
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

    private func input(
        rootfsBase: URL = URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz"),
        currentUpdaterVersion: String = "1.2.3"
    ) -> ApplyRuntimeBundlePreflightInput {
        ApplyRuntimeBundlePreflightInput(
            bundleURL: URL(fileURLWithPath: "/incoming/bundle"),
            backupsDirectory: URL(fileURLWithPath: "/product/backups"),
            rootfsBase: rootfsBase,
            updateFreeSpaceMarginBytes: updateFreeSpaceMarginBytes,
            currentUpdaterVersion: currentUpdaterVersion,
            currentChannel: .stable,
            currentPlatform: "macos-arm64"
        )
    }

    private func operations(
        stagedBundle: URL = URL(fileURLWithPath: "/managed/update-bundle-1.2.3"),
        manifest: UpdateBundleManifest,
        observeRootfsStorage: @escaping (URL, URL) throws -> ApplyRuntimeBundleRootfsStorageObservation = { _, _ in missingRootfsObservation() },
        createDirectory: @escaping (URL, Bool) throws -> Void = { _, _ in },
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void = { _, _, _ in },
        serviceRestartPolicy: @escaping () -> RuntimeServiceRestartPolicy = stoppedPolicy,
        runtimeHealthSnapshot: @escaping () -> RuntimeHealthSnapshot = {
            healthySnapshot()
        },
        requireGuestCapability: @escaping (RuntimeGuestCapabilityRequirement) throws -> Void = { _ in },
        createBackup: @escaping (String) throws -> URL = { _ in URL(fileURLWithPath: "/product/backups/backup-before-1.2.3") },
        directorySize: @escaping (URL) throws -> UInt64 = { _ in 10 },
        event: @escaping (String) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> ApplyRuntimeBundlePreflightOperations {
        ApplyRuntimeBundlePreflightOperations(
            stageBundle: { url in
                event("stage:\(url.path)")
                return stagedBundle
            },
            loadStagedManifest: { url in
                event("manifest:\(url.lastPathComponent)")
                return manifest
            },
            observeRootfsStorage: observeRootfsStorage,
            createDirectory: createDirectory,
            requireFreeSpace: requireFreeSpace,
            serviceRestartPolicy: serviceRestartPolicy,
            runtimeHealthSnapshot: {
                event("health")
                return runtimeHealthSnapshot()
            },
            requireGuestCapability: requireGuestCapability,
            createBackup: createBackup,
            directorySize: directorySize,
            log: log
        )
    }

    private func manifest(
        version: String,
        artifacts: [UpdateBundleArtifact] = [],
        minUpdaterVersion: String? = nil,
        requiresGuestActivation: Bool = false
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 3,
            product: "ai.tirosh.vitalserver.helper",
            helperVersion: version,
            releaseLabel: version,
            targetPlatform: "macos-arm64",
            components: ["updater": version],
            minUpdaterVersion: minUpdaterVersion,
            requiresGuestActivation: requiresGuestActivation,
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts,
            migrations: []
        )
    }
}

private enum TestError: Error, CustomStringConvertible {
    case operationFailed(String)

    var description: String {
        switch self {
        case .operationFailed(let message):
            message
        }
    }
}

private let updateFreeSpaceMarginBytes: UInt64 = 2 * 1024 * 1024 * 1024

private func missingRootfsObservation() -> ApplyRuntimeBundleRootfsStorageObservation {
    ApplyRuntimeBundleRootfsStorageObservation(
        stagedRootfs: URL(fileURLWithPath: "/unused"),
        stagedRootfsExists: false,
        installedRootfsBytes: nil,
        incomingRootfsBytes: nil
    )
}

private func stoppedPolicy() -> RuntimeServiceRestartPolicy {
    RuntimeServiceRestartPolicy(restartVM: false, restartGuestLogSync: false, restartProxy: false, restartWatchdog: false)
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
