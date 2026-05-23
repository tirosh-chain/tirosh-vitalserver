import Foundation
import Core
import Contracts

struct RuntimeCommandExecutor {
    let commandRunner: RuntimeCommandRunner
    let log: (String) -> Void

    func run(_ executable: String, _ arguments: [String]) -> RuntimeProcessResult {
        commandRunner.run(executable, arguments: arguments)
    }

    func runRequired(_ executable: String, _ arguments: [String]) throws {
        log("command started executable=\(executable) arguments=\(arguments.joined(separator: " "))")
        let result = run(executable, arguments)
        try requireSuccess(result, executable: executable, arguments: arguments)
        log("command completed executable=\(executable)")
    }

    func runWritingOutput(_ executable: String, _ arguments: [String], output: URL) throws {
        let result = commandRunner.runWritingOutput(executable, arguments: arguments, output: output)
        try requireSuccess(result, executable: executable, arguments: arguments)
    }

    private func requireSuccess(
        _ result: RuntimeProcessResult,
        executable: String,
        arguments: [String]
    ) throws {
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                log("command stderr executable=\(executable) stderr=\(stderr)")
            }
            log("command failed executable=\(executable) exitCode=\(result.exitCode)")
            throw LauncherError.missingArgument(
                "command failed: \(([executable] + arguments).joined(separator: " "))"
            )
        }
    }
}
