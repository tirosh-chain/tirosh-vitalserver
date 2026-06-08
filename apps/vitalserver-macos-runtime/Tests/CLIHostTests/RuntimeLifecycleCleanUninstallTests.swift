import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeLifecycleCleanUninstallTests: XCTestCase {
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
    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        .notLoaded
    }

    func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
