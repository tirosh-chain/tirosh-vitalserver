import Foundation
import Core
import Contracts

struct RuntimeCommandExecutor {
    let commandRunner: RuntimeCommandRunner
    let log: (String) -> Void
    var recordCommandEvent: (RuntimeEventType, String, [String], RuntimeProcessResult?) -> Void = { _, _, _, _ in }

    func run(_ executable: String, _ arguments: [String]) -> RuntimeProcessResult {
        commandRunner.run(executable, arguments: arguments)
    }

    func runRequired(_ executable: String, _ arguments: [String]) throws {
        log("command started executable=\(executable) arguments=\(arguments.joined(separator: " "))")
        recordCommandEvent(.runtimeCommandStarted, executable, arguments, nil)
        let result = run(executable, arguments)
        do {
            try requireSuccess(result, executable: executable, arguments: arguments)
        } catch {
            recordCommandEvent(.runtimeCommandFailed, executable, arguments, result)
            throw error
        }
        log("command completed executable=\(executable)")
        recordCommandEvent(.runtimeCommandCompleted, executable, arguments, result)
    }

    func runWritingOutput(_ executable: String, _ arguments: [String], output: URL) throws {
        log("command started executable=\(executable) arguments=\(arguments.joined(separator: " ")) output=\(output.path)")
        recordCommandEvent(.runtimeCommandStarted, executable, arguments, nil)
        let result = commandRunner.runWritingOutput(executable, arguments: arguments, output: output)
        do {
            try requireSuccess(result, executable: executable, arguments: arguments)
        } catch {
            recordCommandEvent(.runtimeCommandFailed, executable, arguments, result)
            throw error
        }
        log("command completed executable=\(executable) output=\(output.path)")
        recordCommandEvent(.runtimeCommandCompleted, executable, arguments, result)
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
