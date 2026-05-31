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
                return RuntimeServiceRestartPolicy(restartVM: true, restartProxy: false, restartWatchdog: false)
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
