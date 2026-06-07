import Foundation
import Application
import Contracts
import Errors

public struct SystemRuntimeCommandRunner: RuntimeCommandRunner {
    public init() {}

    public func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let output = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
            let decodedOutput = decodeOutput(output, stream: .stdout)
            let decodedErrorOutput = decodeOutput(errorOutput, stream: .stderr)
            return RuntimeProcessResult(
                exitCode: process.terminationStatus,
                stdout: decodedOutput.text,
                stderr: decodedErrorOutput.text,
                outputIssues: [decodedOutput.issue, decodedErrorOutput.issue].compactMap { $0 }
            )
        } catch {
            let message = error.localizedDescription
            return RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: message,
                executionIssue: RuntimeProcessExecutionIssue(
                    kind: .processLaunchFailed,
                    message: message
                )
            )
        }
    }

    public func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        let process = Process()
        let stderr = Pipe()
        let outputHandle: FileHandle

        do {
            try Data().write(to: output)
            outputHandle = try FileHandle(forWritingTo: output)
        } catch {
            let message = error.localizedDescription
            return RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: message,
                executionIssue: RuntimeProcessExecutionIssue(
                    kind: .outputFilePreparationFailed,
                    message: message
                )
            )
        }
        defer {
            try? outputHandle.close()
        }

        do {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputHandle
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
            let decodedErrorOutput = decodeOutput(errorOutput, stream: .stderr)
            return RuntimeProcessResult(
                exitCode: process.terminationStatus,
                stdout: "",
                stderr: decodedErrorOutput.text,
                outputIssues: [decodedErrorOutput.issue].compactMap { $0 }
            )
        } catch {
            let message = error.localizedDescription
            return RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: message,
                executionIssue: RuntimeProcessExecutionIssue(
                    kind: .processLaunchFailed,
                    message: message
                )
            )
        }
    }

    private func decodeOutput(
        _ data: Data,
        stream: RuntimeCommandOutputStream
    ) -> (text: String, issue: RuntimeCommandOutputIssue?) {
        guard !data.isEmpty else {
            return ("", nil)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return (
                "",
                RuntimeCommandOutputIssue(
                    stream: stream,
                    message: "command \(stream.rawValue) is not valid UTF-8"
                )
            )
        }
        return (text, nil)
    }
}
