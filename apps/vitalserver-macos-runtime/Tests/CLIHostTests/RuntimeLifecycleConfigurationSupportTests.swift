import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
@testable import CLIHost
import XCTest

final class RuntimeLifecycleConfigurationSupportTests: XCTestCase {
    func testSetSystemSleepPreventionReturnsWithoutCommandsWhenPlistIsMissing() throws {
        let harness = Harness()

        try harness.lifecycle.setSystemSleepPrevention(true)

        XCTAssertTrue(harness.commandRunner.commands.isEmpty)
        XCTAssertTrue(harness.serviceManager.startCalls.isEmpty)
        XCTAssertTrue(harness.serviceManager.stopCalls.isEmpty)
        XCTAssertTrue(harness.serviceManager.setEnabledCalls.isEmpty)
    }

    func testSetSystemSleepPreventionFailsWhenPlistInspectionFails() {
        let harness = Harness()
        harness.fileStore.pathStates[harness.sleepPreventionPlist.path] = .inspectFailed("permission denied")

        XCTAssertThrowsError(try harness.lifecycle.setSystemSleepPrevention(true)) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertEqual(
                message,
                "system sleep prevention service inspection failed path=\(harness.sleepPreventionPlist.path) reason=permission denied"
            )
        }
        XCTAssertTrue(harness.commandRunner.commands.isEmpty)
        XCTAssertTrue(harness.serviceManager.startCalls.isEmpty)
    }

    func testSetSystemSleepPreventionFailsWhenPlistPathStateIsUnexpected() {
        let harness = Harness()
        harness.fileStore.pathStates[harness.sleepPreventionPlist.path] = .directory

        XCTAssertThrowsError(try harness.lifecycle.setSystemSleepPrevention(false)) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertEqual(
                message,
                "system sleep prevention service path state is unexpected path=\(harness.sleepPreventionPlist.path) state=directory"
            )
        }
        XCTAssertTrue(harness.commandRunner.commands.isEmpty)
        XCTAssertTrue(harness.serviceManager.stopCalls.isEmpty)
    }

    func testSetSystemSleepPreventionDisablesLoadedServiceWhenPlistIsFile() throws {
        let harness = Harness()
        harness.fileStore.files[harness.sleepPreventionPlist] = Data()
        harness.serviceManager.states[.sleepPrevention] = .loaded

        try harness.lifecycle.setSystemSleepPrevention(false)

        XCTAssertEqual(harness.commandRunner.commands, [
            "/bin/launchctl disable system/\(RuntimeManagedService.sleepPrevention.label)",
        ])
        XCTAssertEqual(harness.serviceManager.stopCalls, [.sleepPrevention])
        XCTAssertTrue(harness.serviceManager.startCalls.isEmpty)
    }

    private final class Harness {
        let productRoot: URL
        let installedPaths: InstalledRuntimePaths
        let fileStore = RuntimeFileStoreSpy()
        let commandRunner = CommandRunnerSpy()
        let serviceManager = ServiceManagerSpy()
        let sleepPreventionPlist: URL
        let lifecycle: RuntimeLifecycle

        init() {
            productRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("runtime-lifecycle-config-\(UUID().uuidString)")
            installedPaths = InstalledRuntimePaths(productRoot: productRoot)
            try? FileManager.default.createDirectory(
                at: installedPaths.statusDirectory,
                withIntermediateDirectories: true
            )
            sleepPreventionPlist = URL(fileURLWithPath: RuntimeManagedServicePaths.launchDaemonPlist(.sleepPrevention))
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

        deinit {
            try? FileManager.default.removeItem(at: productRoot)
        }
    }
}

private final class CommandRunnerSpy: RuntimeCommandRunner {
    var commands: [String] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        commands.append(([executable] + arguments).joined(separator: " "))
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}

private final class ServiceManagerSpy: RuntimeServiceManager {
    var states: [RuntimeManagedService: RuntimeServiceState] = [:]
    var startCalls: [RuntimeManagedService] = []
    var stopCalls: [RuntimeManagedService] = []
    var setEnabledCalls: [(service: RuntimeManagedService, enabled: Bool)] = []

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        states[service] ?? .notLoaded
    }

    func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult {
        startCalls.append(service)
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        stopCalls.append(service)
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        setEnabledCalls.append((service, enabled))
        return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
