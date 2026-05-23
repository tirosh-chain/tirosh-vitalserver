import Foundation
import RuntimeCore
import RuntimeContracts
@testable import HostRuntimeControl
import XCTest

final class RuntimeApplyBundlePreflightRunnerTests: XCTestCase {
    func testPrepareBuildsPreflightContextInOrder() throws {
        let inputBundle = URL(fileURLWithPath: "/incoming/bundle")
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let backupsDirectory = URL(fileURLWithPath: "/product/backups")
        let rootfsBase = URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        let stagedRootfs = stagedBundle.appendingPathComponent(Constants.Artifacts.rootfsBase)
        let backup = URL(fileURLWithPath: "/product/backups/backup-before-1.2.3")
        var events: [String] = []
        var requiredSpace: (url: URL, bytes: UInt64, operation: RuntimeOperation)?

        let runner = RuntimeApplyBundlePreflightRunner(
            stageBundle: { url in
                events.append("stage:\(url.path)")
                return stagedBundle
            },
            loadManifest: { url in
                events.append("manifest:\(url.lastPathComponent)")
                return self.manifest(
                    version: "1.2.3",
                    artifacts: [
                        UpdateBundleArtifact(
                            name: Constants.Artifacts.rootfsBase,
                            type: .rootfsBase,
                            sha256: "abc",
                            size: 20
                        ),
                    ]
                )
            },
            fileExists: { url in
                url == stagedRootfs
            },
            createDirectory: { url, withIntermediateDirectories in
                events.append("mkdir:\(url.path):\(withIntermediateDirectories)")
            },
            fileSize: { url in
                switch url {
                case rootfsBase:
                    return 10
                case stagedRootfs:
                    return 20
                default:
                    return 5
                }
            },
            requireFreeSpace: { url, bytes, operation in
                requiredSpace = (url, bytes, operation)
            },
            checkCompatibility: { manifest in
                events.append("compatibility:\(manifest.version)")
            },
            serviceRestartPolicy: {
                events.append("policy")
                return RuntimeServiceRestartPolicy(restartVM: true, restartProxy: false, restartWatchdog: true)
            },
            createBackup: { reason in
                events.append("backup:\(reason)")
                return backup
            },
            directorySize: { url in
                events.append("du:\(url.path)")
                return 30
            },
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
            restartProxy: false,
            restartWatchdog: true
        ))
        XCTAssertEqual(requiredSpace?.url, backupsDirectory)
        XCTAssertEqual(requiredSpace?.bytes, 30 + Constants.Runtime.updateFreeSpaceMarginBytes)
        XCTAssertEqual(requiredSpace?.operation, .applyBundle)
        XCTAssertEqual(events, [
            "stage:/incoming/bundle",
            "manifest:manifest.json",
            "compatibility:1.2.3",
            "mkdir:/product/backups:true",
            "policy",
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
            loadManifest: { _ in self.manifest(version: "1.2.3") },
            fileExists: { _ in
                XCTFail("rootfs existence should not be checked")
                return false
            },
            createDirectory: { _, _ in },
            fileSize: { _ in
                XCTFail("rootfs size should not be checked")
                return 0
            },
            requireFreeSpace: { _, bytes, _ in requiredSpace = bytes },
            checkCompatibility: { _ in },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(restartVM: false, restartProxy: true, restartWatchdog: false)
            },
            createBackup: { _ in backup },
            directorySize: { _ in 10 },
            log: { _ in }
        )

        let context = try runner.prepare(
            bundleURL: inputBundle,
            backupsDirectory: backupsDirectory,
            rootfsBase: URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        )

        XCTAssertNil(context.stagedRootfs)
        XCTAssertFalse(context.updatesRootfsBase)
        XCTAssertEqual(requiredSpace, Constants.Runtime.updateFreeSpaceMarginBytes)
    }

    func testPrepareFailsWhenStagedRootfsIsMissing() {
        let stagedBundle = URL(fileURLWithPath: "/managed/update-bundle-1.2.3")
        let runner = RuntimeApplyBundlePreflightRunner(
            stageBundle: { _ in stagedBundle },
            loadManifest: { _ in
                self.manifest(
                    version: "1.2.3",
                    artifacts: [
                        UpdateBundleArtifact(
                            name: Constants.Artifacts.rootfsBase,
                            type: .rootfsBase,
                            sha256: "abc",
                            size: 20
                        ),
                    ]
                )
            },
            fileExists: { _ in false },
            createDirectory: { _, _ in XCTFail("should not create backup directory") },
            fileSize: { _ in 0 },
            requireFreeSpace: { _, _, _ in },
            checkCompatibility: { _ in },
            serviceRestartPolicy: {
                RuntimeServiceRestartPolicy(restartVM: false, restartProxy: false, restartWatchdog: false)
            },
            createBackup: { _ in URL(fileURLWithPath: "/backup") },
            directorySize: { _ in 0 },
            log: { _ in }
        )

        XCTAssertThrowsError(try runner.prepare(
            bundleURL: URL(fileURLWithPath: "/incoming/bundle"),
            backupsDirectory: URL(fileURLWithPath: "/product/backups"),
            rootfsBase: URL(fileURLWithPath: "/product/runtime/rootfs-base.raw.gz")
        )) { error in
            XCTAssertEqual(String(describing: error), String(describing: LauncherError.missingFile(
                stagedBundle.appendingPathComponent(Constants.Artifacts.rootfsBase).path
            )))
        }
    }

    private func manifest(
        version: String,
        artifacts: [UpdateBundleArtifact] = []
    ) -> UpdateBundleManifest {
        UpdateBundleManifest(
            schemaVersion: 2,
            product: Constants.Product.identifier,
            helperVersion: version,
            targetPlatforms: ["macos-arm64"],
            components: ["updater": version],
            requiresGuestActivation: false,
            createdAt: "2026-05-22T00:00:00Z",
            artifacts: artifacts,
            migrations: []
        )
    }
}
