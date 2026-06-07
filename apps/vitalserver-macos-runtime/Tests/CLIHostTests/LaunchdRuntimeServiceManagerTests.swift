import Foundation
import Contracts
import Application
import Domain
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class LaunchdRuntimeServiceManagerTests: XCTestCase {
    func testLaunchctlMissingServiceIsNotLoaded() {
        let runner = LaunchdCommandRunnerSpy(result: RuntimeProcessResult(
            exitCode: 113,
            stdout: "",
            stderr: "Could not find service \"ai.tirosh.vitalserver.helper.vm\" in domain\n"
        ))
        let manager = LaunchdRuntimeServiceManager(commandRunner: runner)

        XCTAssertEqual(manager.state(service: .vm), .notLoaded)
    }

    func testLaunchctlPermissionFailureIsNotCollapsedToNotLoaded() {
        let runner = LaunchdCommandRunnerSpy(result: RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Operation not permitted\n"
        ))
        let manager = LaunchdRuntimeServiceManager(commandRunner: runner)

        guard case .permissionDenied(let reason) = manager.state(service: .vm) else {
            return XCTFail("Expected permissionDenied")
        }
        XCTAssertTrue(reason.contains("Operation not permitted"))
    }

    func testLaunchctlUnknownFailureIsReadFailed() {
        let runner = LaunchdCommandRunnerSpy(result: RuntimeProcessResult(
            exitCode: 5,
            stdout: "",
            stderr: "Input/output error\n"
        ))
        let manager = LaunchdRuntimeServiceManager(commandRunner: runner)

        guard case .readFailed(let reason) = manager.state(service: .vm) else {
            return XCTFail("Expected readFailed")
        }
        XCTAssertTrue(reason.contains("Input/output error"))
    }

    func testStartReturnsBootstrapResultWhenBootstrapSucceeds() {
        let runner = LaunchdCommandRunnerSpy(results: [
            RuntimeProcessResult(exitCode: 0, stdout: "bootstrapped", stderr: ""),
        ])
        let manager = LaunchdRuntimeServiceManager(commandRunner: runner)

        let result = manager.start(service: .proxy, plist: "/Library/LaunchDaemons/proxy.plist")

        XCTAssertEqual(result.stdout, "bootstrapped")
        XCTAssertEqual(runner.commands, [
            "/bin/launchctl bootstrap system /Library/LaunchDaemons/proxy.plist",
        ])
    }

    func testStartReturnsKickstartResultWhenBootstrapFails() {
        let runner = LaunchdCommandRunnerSpy(results: [
            RuntimeProcessResult(exitCode: 5, stdout: "", stderr: "bootstrap failed"),
            RuntimeProcessResult(exitCode: 7, stdout: "", stderr: "kickstart failed"),
        ])
        let manager = LaunchdRuntimeServiceManager(commandRunner: runner)

        let result = manager.start(service: .proxy, plist: "/Library/LaunchDaemons/proxy.plist")

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stderr, "kickstart failed")
        XCTAssertEqual(runner.commands, [
            "/bin/launchctl bootstrap system /Library/LaunchDaemons/proxy.plist",
            "/bin/launchctl kickstart -k system/\(RuntimeManagedService.proxy.label)",
        ])
    }

    func testRestartAndStopReturnLaunchctlResults() {
        let runner = LaunchdCommandRunnerSpy(results: [
            RuntimeProcessResult(exitCode: 4, stdout: "", stderr: "kickstart failed"),
            RuntimeProcessResult(exitCode: 6, stdout: "", stderr: "bootout failed"),
        ])
        let manager = LaunchdRuntimeServiceManager(commandRunner: runner)

        let restart = manager.restart(service: .watchdog)
        let stop = manager.stop(service: .watchdog)

        XCTAssertEqual(restart.exitCode, 4)
        XCTAssertEqual(restart.stderr, "kickstart failed")
        XCTAssertEqual(stop.exitCode, 6)
        XCTAssertEqual(stop.stderr, "bootout failed")
        XCTAssertEqual(runner.commands, [
            "/bin/launchctl kickstart -k system/\(RuntimeManagedService.watchdog.label)",
            "/bin/launchctl bootout system/\(RuntimeManagedService.watchdog.label)",
        ])
    }
}

private final class LaunchdCommandRunnerSpy: RuntimeCommandRunner {
    private var results: [RuntimeProcessResult]
    private let fallbackResult: RuntimeProcessResult
    var commands: [String] = []

    init(result: RuntimeProcessResult) {
        self.results = [result]
        self.fallbackResult = result
    }

    init(results: [RuntimeProcessResult]) {
        self.results = results
        self.fallbackResult = results.last ?? RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        commands.append(([executable] + arguments).joined(separator: " "))
        guard !results.isEmpty else {
            return fallbackResult
        }
        return results.removeFirst()
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}
