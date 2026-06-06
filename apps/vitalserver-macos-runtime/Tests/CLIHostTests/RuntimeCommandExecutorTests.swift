import Foundation
import Application
import Contracts
import Domain
import Workflow
@testable import CLIHost
import XCTest
import Errors

final class RuntimeCommandExecutorTests: XCTestCase {
    func testRunRequiredLogsStartAndCompletionOnSuccess() throws {
        let runner = CommandRunnerSpy()
        let harness = CommandExecutorHarness(runner: runner)

        try harness.executor.runRequired("/bin/tool", ["--flag"])

        XCTAssertEqual(runner.commands, ["run:/bin/tool --flag"])
        XCTAssertEqual(harness.logs, [
            "command started executable=/bin/tool arguments=--flag",
            "command completed executable=/bin/tool",
        ])
        XCTAssertEqual(harness.events.map(\.type), [.runtimeCommandStarted, .runtimeCommandCompleted])
    }

    func testRunRequiredLogsStderrAndThrowsOnFailure() {
        let runner = CommandRunnerSpy()
        runner.nextResult = RuntimeProcessResult(exitCode: 2, stdout: "", stderr: "bad\n")
        let harness = CommandExecutorHarness(runner: runner)

        XCTAssertThrowsError(try harness.executor.runRequired("/bin/tool", ["--flag"])) { error in
            XCTAssertEqual(
                String(describing: error),
                String(describing: RuntimeCommandExecutionError.commandFailed("command failed: /bin/tool --flag"))
            )
        }
        XCTAssertEqual(harness.logs, [
            "command started executable=/bin/tool arguments=--flag",
            "command stderr executable=/bin/tool stderr=bad",
            "command failed executable=/bin/tool exitCode=2",
        ])
        XCTAssertEqual(harness.events.map(\.type), [.runtimeCommandStarted, .runtimeCommandFailed])
    }

    func testRunWritingOutputThrowsOnFailure() {
        let runner = CommandRunnerSpy()
        runner.nextWriteResult = RuntimeProcessResult(exitCode: 3, stdout: "", stderr: "write failed")
        let harness = CommandExecutorHarness(runner: runner)

        XCTAssertThrowsError(try harness.executor.runWritingOutput(
            "/bin/tool",
            ["--out"],
            output: URL(fileURLWithPath: "/tmp/out")
        ))
        XCTAssertEqual(runner.commands, ["write:/bin/tool --out /tmp/out"])
        XCTAssertEqual(harness.logs, [
            "command started executable=/bin/tool arguments=--out output=/tmp/out",
            "command stderr executable=/bin/tool stderr=write failed",
            "command failed executable=/bin/tool exitCode=3",
        ])
        XCTAssertEqual(harness.events.map(\.type), [.runtimeCommandStarted, .runtimeCommandFailed])
    }
}

private final class CommandExecutorHarness {
    let runner: CommandRunnerSpy
    var logs: [String] = []
    var events: [(type: RuntimeEventType, executable: String, arguments: [String], result: RuntimeProcessResult?)] = []

    init(runner: CommandRunnerSpy) {
        self.runner = runner
    }

    var executor: RuntimeCommandExecutor {
        RuntimeCommandExecutor(
            commandRunner: runner,
            log: { message in
                self.logs.append(message)
            },
            recordCommandEvent: { type, executable, arguments, result in
                self.events.append((type, executable, arguments, result))
            }
        )
    }
}

private final class CommandRunnerSpy: RuntimeCommandRunner {
    var commands: [String] = []
    var nextResult = RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
    var nextWriteResult = RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        commands.append("run:\(([executable] + arguments).joined(separator: " "))")
        return nextResult
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        commands.append("write:\(([executable] + arguments).joined(separator: " ")) \(output.path)")
        return nextWriteResult
    }
}
