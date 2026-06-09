import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import Workflow
@testable import CLIHost
import XCTest

final class RuntimeLifecycleCleanUninstallTests: XCTestCase {
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
                configuredExternalVitalFilesDirectory: {
                    RuntimeConfiguredExternalVitalFilesDirectoryRead(externalDirectory: nil, failure: nil)
                },
                serviceState: { _ in .notLoaded },
                createRedisBackup: {
                    events.append("backup")
                },
                disableRuntimeServicesForUninstall: {
                    events.append("disable")
                },
                stopRuntimeServices: {
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
                log: { events.append("log:\($0)") }
            )
        )

        try runner.run(RuntimeUninstallCommand(clean: true, forceClean: true))

        XCTAssertTrue(events.contains("disable"))
        XCTAssertTrue(events.contains("force-stop"))
        XCTAssertTrue(events.contains("cleanup:clean=true"))
        XCTAssertFalse(events.contains("stop"))
    }

    func testForceCleanUninstallRecoveryUnloadsLaunchdServicesWhenVMPidFileIsMissing() throws {
        let harness = Harness()
        harness.serviceManager.states[.vm] = .loaded
        harness.serviceManager.states[.sleepPrevention] = .loaded

        try harness.lifecycle.stopRuntimeServicesForCleanUninstallRecovery()

        XCTAssertEqual(harness.serviceManager.stoppedLabels, [
            RuntimeManagedService.vm.label,
            RuntimeManagedService.sleepPrevention.label,
        ])
    }

    func testCleanUninstallSkipsMissingProxyPortCleanupWhenRuntimeArtifactsAreAlreadyAbsent() throws {
        let harness = Harness()
        harness.fileStore.directories.insert(harness.installedPaths.productRoot)
        harness.fileStore.directories.insert(harness.installedPaths.dataDirectory)

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
