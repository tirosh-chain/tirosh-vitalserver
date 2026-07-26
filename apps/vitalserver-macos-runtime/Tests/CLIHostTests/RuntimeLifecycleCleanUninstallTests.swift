import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import Workflow
@testable import CLIHost
import XCTest

final class RuntimeLifecycleCleanUninstallTests: XCTestCase {
    func testConfiguredVitalFilesSQLiteSnapshotIsReadAfterOperationLeaseAcquisition() throws {
        let installedPaths = InstalledRuntimePaths(
            productRoot: URL(fileURLWithPath: "/lease-ordered-uninstall-product")
        )
        let fileStore = RuntimeFileStoreSpy()
        var ordering: [String] = []
        let runner = RuntimeUninstallComposition.make(
            context: RuntimeUninstallCompositionContext(
                installedPaths: installedPaths,
                pidFile: installedPaths.pidFile
            ),
            operations: RuntimeUninstallCompositionOperations(
                fileStore: fileStore,
                configuredVitalFilesDirectories: {
                    ordering.append("read-host-settings")
                    return configuredVitalFilesDirectories(
                        installedPaths.helperManagedDefaultVitalFilesDirectory
                    )
                },
                serviceState: { _ in .notLoaded },
                createVitalServerBackup: {},
                disableAutomaticBackupScheduler: {},
                disableRuntimeServicesForUninstall: {},
                stopRuntimeServicesForUninstall: {},
                forceStopRuntimeServicesForUninstall: {},
                clearLaunchdDisabledOverridesAfterUninstall: {},
                cleanupHostProxyPortAfterStop: { _ in },
                packageReceiptStates: { [] },
                openFilesInDirectory: { _ in
                    RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                },
                forgetPackageReceipt: { _ in
                    RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                },
                now: { Date(timeIntervalSince1970: 0) },
                log: { _ in },
                stateWriter: RuntimeUninstallStateWriter(
                    acquireOperationLease: {
                        ordering.append("acquire-lease")
                    },
                    releaseOperationLease: {
                        ordering.append("release-lease")
                    },
                    writeState: { _, _, _, _ in },
                    relocateProductRoot: { _, _ in }
                )
            )
        )

        XCTAssertEqual(ordering, [])
        try runner.run(RuntimeUninstallCommand(clean: true))

        XCTAssertEqual(Array(ordering.prefix(2)), [
            "acquire-lease",
            "read-host-settings",
        ])
        XCTAssertEqual(ordering.last, "release-lease")
    }

    func testCleanUninstallForcesRuntimeServiceCleanupWhenGracefulStopFails() throws {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/clean-uninstall-product"))
        let fileStore = RuntimeFileStoreSpy()
        var events: [String] = []
        let runner = RuntimeUninstallComposition.make(
            context: RuntimeUninstallCompositionContext(
                installedPaths: installedPaths,
                pidFile: installedPaths.pidFile
            ),
            operations: RuntimeUninstallCompositionOperations(
                fileStore: fileStore,
                configuredVitalFilesDirectories: {
                    configuredVitalFilesDirectories(
                        installedPaths.helperManagedDefaultVitalFilesDirectory
                    )
                },
                serviceState: { _ in .notLoaded },
                createVitalServerBackup: {
                    events.append("backup")
                },
                disableAutomaticBackupScheduler: {
                    events.append("disable-automatic-backup")
                },
                disableRuntimeServicesForUninstall: {
                    events.append("disable")
                },
                stopRuntimeServicesForUninstall: {
                    events.append("stop")
                    throw NSError(domain: "test", code: 1)
                },
                forceStopRuntimeServicesForUninstall: {
                    events.append("force-stop")
                },
                clearLaunchdDisabledOverridesAfterUninstall: {
                    events.append("clear-disabled-overrides")
                },
                cleanupHostProxyPortAfterStop: { clean in
                    events.append("cleanup:clean=\(clean)")
                },
                packageReceiptStates: { [] },
                openFilesInDirectory: { _ in RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "") },
                forgetPackageReceipt: { identifier in
                    events.append("forget:\(identifier)")
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                },
                now: { Date(timeIntervalSince1970: 0) },
                log: { events.append("log:\($0)") },
                stateWriter: testUninstallStateWriter()
            )
        )

        try runner.run(RuntimeUninstallCommand(clean: true))

        XCTAssertTrue(events.contains("disable"))
        XCTAssertTrue(events.contains("stop"))
        XCTAssertTrue(events.contains {
            $0.hasPrefix("log:clean uninstall graceful stop failed; forcing runtime service cleanup reason=")
        })
        XCTAssertTrue(events.contains("force-stop"))
        XCTAssertTrue(events.contains("cleanup:clean=true"))
        XCTAssertFalse(events.contains("backup"))
    }

    func testForceCleanUninstallUsesForceStopRuntimeServicesHook() throws {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/clean-uninstall-product"))
        let fileStore = RuntimeFileStoreSpy()
        var events: [String] = []
        let runner = RuntimeUninstallComposition.make(
            context: RuntimeUninstallCompositionContext(
                installedPaths: installedPaths,
                pidFile: installedPaths.pidFile
            ),
            operations: RuntimeUninstallCompositionOperations(
                fileStore: fileStore,
                configuredVitalFilesDirectories: {
                    configuredVitalFilesDirectories(
                        installedPaths.helperManagedDefaultVitalFilesDirectory
                    )
                },
                serviceState: { _ in .notLoaded },
                createVitalServerBackup: {
                    events.append("backup")
                },
                disableAutomaticBackupScheduler: {
                    events.append("disable-automatic-backup")
                },
                disableRuntimeServicesForUninstall: {
                    events.append("disable")
                },
                stopRuntimeServicesForUninstall: {
                    events.append("stop")
                },
                forceStopRuntimeServicesForUninstall: {
                    events.append("force-stop")
                },
                clearLaunchdDisabledOverridesAfterUninstall: {
                    events.append("clear-disabled-overrides")
                },
                cleanupHostProxyPortAfterStop: { clean in
                    events.append("cleanup:clean=\(clean)")
                },
                packageReceiptStates: { [] },
                openFilesInDirectory: { _ in RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "") },
                forgetPackageReceipt: { identifier in
                    events.append("forget:\(identifier)")
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                },
                now: { Date(timeIntervalSince1970: 0) },
                log: { events.append("log:\($0)") },
                stateWriter: testUninstallStateWriter()
            )
        )

        try runner.run(RuntimeUninstallCommand(clean: true, forceClean: true))

        XCTAssertTrue(events.contains("disable"))
        XCTAssertTrue(events.contains("force-stop"))
        XCTAssertTrue(events.contains("cleanup:clean=true"))
        XCTAssertFalse(events.contains("stop"))
    }

    func testCleanUninstallPreservesConfiguredExternalVitalFilesDirectoryWithoutOwnedEntries() throws {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/clean-uninstall-product"))
        let externalVitalFilesDirectory = URL(fileURLWithPath: "/Volumes/ClinicalData/VitalFiles")
        let externalVitalFile = externalVitalFilesDirectory.appendingPathComponent("patient.vital")
        let fileStore = RuntimeFileStoreSpy()
        fileStore.directories.insert(externalVitalFilesDirectory)
        fileStore.files[externalVitalFile] = Data("vital-data".utf8)
        var events: [String] = []
        let runner = RuntimeUninstallComposition.make(
            context: RuntimeUninstallCompositionContext(
                installedPaths: installedPaths,
                pidFile: installedPaths.pidFile
            ),
            operations: RuntimeUninstallCompositionOperations(
                fileStore: fileStore,
                configuredVitalFilesDirectories: {
                    configuredVitalFilesDirectories(externalVitalFilesDirectory)
                },
                serviceState: { _ in .notLoaded },
                createVitalServerBackup: {},
                disableAutomaticBackupScheduler: {},
                disableRuntimeServicesForUninstall: {},
                stopRuntimeServicesForUninstall: {},
                forceStopRuntimeServicesForUninstall: {},
                clearLaunchdDisabledOverridesAfterUninstall: {},
                cleanupHostProxyPortAfterStop: { _ in },
                packageReceiptStates: { [] },
                openFilesInDirectory: { _ in RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "") },
                forgetPackageReceipt: { _ in RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "") },
                now: { Date(timeIntervalSince1970: 0) },
                log: { events.append($0) },
                stateWriter: testUninstallStateWriter()
            )
        )

        try runner.run(RuntimeUninstallCommand(clean: true))

        XCTAssertTrue(fileStore.directoryExists(externalVitalFilesDirectory))
        XCTAssertEqual(fileStore.files[externalVitalFile], Data("vital-data".utf8))
        XCTAssertFalse(fileStore.removed.contains(externalVitalFilesDirectory))
        XCTAssertTrue(events.contains(
            "preserved configured external vital files directory path=/Volumes/ClinicalData/VitalFiles reason=no-product-owned-removal-contract"
        ))
    }

    func testForceCleanUninstallRecoveryUnloadsLaunchdServicesWhenVMPidFileIsMissing() throws {
        let harness = Harness()
        harness.serviceManager.states[.vm] = .loaded
        harness.serviceManager.states[.sleepPrevention] = .loaded
        harness.serviceManager.states[.platformAgent] = .loaded

        try harness.lifecycle.stopRuntimeServicesForCleanUninstallRecovery()

        XCTAssertEqual(harness.serviceManager.stoppedLabels, [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.sleepPrevention.label,
            RuntimeManagedService.platformAgent.label,
        ])
    }

    func testCleanUninstallServiceStopIncludesPlatformAgentLast() throws {
        let harness = Harness()
        for service in RuntimeManagedService.uninstallOrder {
            harness.serviceManager.states[service] = .loaded
        }

        try harness.lifecycle.stopRuntimeServicesForUninstall()

        XCTAssertEqual(
            harness.serviceManager.stoppedLabels,
            RuntimeManagedService.uninstallOrder.map(\.label)
        )
    }

    func testCleanUninstallSkipsMissingProxyPortCleanupWhenRuntimeArtifactsAreAlreadyAbsent() throws {
        let harness = Harness()
        harness.fileStore.directories.insert(harness.installedPaths.productRoot)
        harness.fileStore.directories.insert(harness.installedPaths.dataDirectory)

        try harness.lifecycle.cleanupHostProxyPortAfterStopForUninstall(clean: true)

        XCTAssertFalse(harness.commandRunner.commands.contains { $0.executable == Constants.Commands.lsof })
        XCTAssertFalse(harness.commandRunner.commands.contains { $0.executable == Constants.Commands.kill })
    }

    func testCleanUninstallSkipsMissingProxyPortCleanupWhenOnlyRuntimeToolsRemain() throws {
        let harness = Harness()
        harness.fileStore.directories.insert(harness.installedPaths.productRoot)
        harness.fileStore.directories.insert(harness.installedPaths.statusDirectory)
        harness.fileStore.files[harness.installedPaths.launcher] = Data()
        harness.fileStore.files[URL(fileURLWithPath: Constants.InstallPaths.proxyRun)] = Data()

        try harness.lifecycle.cleanupHostProxyPortAfterStopForUninstall(clean: true)

        XCTAssertFalse(harness.commandRunner.commands.contains { $0.executable == Constants.Commands.lsof })
        XCTAssertFalse(harness.commandRunner.commands.contains { $0.executable == Constants.Commands.kill })
    }

    func testCleanUninstallStillFailsMissingProxyPortWhenRuntimeArtifactsRemain() {
        let harness = Harness()
        harness.fileStore.directories.insert(harness.installedPaths.nginxDirectory)

        XCTAssertThrowsError(try harness.lifecycle.cleanupHostProxyPortAfterStopForUninstall(clean: true)) { error in
            XCTAssertTrue(String(describing: error).contains("failed to read configured Host proxy port"))
        }
    }

    func testStandardUninstallStillFailsMissingProxyPortCleanup() {
        let harness = Harness()

        XCTAssertThrowsError(try harness.lifecycle.cleanupHostProxyPortAfterStopForUninstall(clean: false)) { error in
            XCTAssertTrue(String(describing: error).contains("failed to read configured Host proxy port"))
        }
    }

    private final class Harness {
        let productRoot: URL
        let installedPaths: InstalledRuntimePaths
        let fileStore = RuntimeFileStoreSpy()
        let commandRunner = CleanUninstallCommandRunnerSpy()
        let serviceManager = CleanUninstallServiceManagerSpy()
        let lifecycle: RuntimeLifecycle

        init() {
            productRoot = URL(fileURLWithPath: "/clean-uninstall-product")
            installedPaths = InstalledRuntimePaths(productRoot: productRoot)
            lifecycle = RuntimeLifecycle(
                paths: LauncherPaths(
                    home: installedPaths.runtimeHome,
                    installed: installedPaths,
                    config: installedPaths.vmConfig,
                    pidFile: installedPaths.pidFile
                ),
                commandRunner: commandRunner,
                serviceManager: serviceManager,
                fileStore: fileStore
            )
        }
    }
}

private func configuredVitalFilesDirectories(
    _ directory: URL,
    revision: Int = 1
) -> RuntimeConfiguredVitalFilesDirectoriesRead {
    .loaded(RuntimeConfiguredVitalFilesDirectoriesSnapshot(
        revision: revision,
        appliedRevision: nil,
        directories: [
            RuntimeConfiguredVitalFilesDirectory(
                source: .desired(revision: revision),
                directory: directory
            ),
        ]
    ))
}

private func testUninstallStateWriter() -> RuntimeUninstallStateWriter {
    RuntimeUninstallStateWriter(
        acquireOperationLease: {},
        releaseOperationLease: {},
        writeState: { _, _, _, _ in },
        relocateProductRoot: { _, _ in }
    )
}

private struct CleanUninstallCommandRequest: Equatable {
    let executable: String
    let arguments: [String]
}

private final class CleanUninstallCommandRunnerSpy: RuntimeCommandRunner {
    var commands: [CleanUninstallCommandRequest] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        commands.append(CleanUninstallCommandRequest(executable: executable, arguments: arguments))
        return RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}

private final class CleanUninstallServiceManagerSpy: RuntimeServiceManager {
    var states: [RuntimeManagedService: RuntimeServiceState] = [:]
    var stoppedLabels: [String] = []

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        states[service] ?? .notLoaded
    }

    func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult {
        states[service] = .loaded
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        stoppedLabels.append(service.label)
        states[service] = .notLoaded
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
