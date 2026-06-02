import Foundation
import Contracts
import Core
@testable import HostCLI
import XCTest

final class LaunchdRuntimeServiceManagerTests: XCTestCase {
    func testLaunchctlMissingServiceIsNotLoaded() {
        let runner = LaunchdCommandRunnerSpy(result: RuntimeProcessResult(
            exitCode: 113,
            stdout: "",
            stderr: "Could not find service \"com.tirosh.vitalserver-vm\" in domain\n"
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
}

private final class LaunchdCommandRunnerSpy: RuntimeCommandRunner {
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
