import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var summary: String {
        let output = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if output.isEmpty {
            return exitCode == 0
                ? AppConstants.StatusText.done
                : AppConstants.StatusText.commandFailed(exitCode: exitCode)
        }
        return output
    }
}

enum ProcessRunner {
    static func run(_ executable: String, arguments: [String]) async -> ProcessResult {
        await Task.detached {
            runSync(executable, arguments: arguments)
        }.value
    }

    static func runSync(_ executable: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: read(stdout),
                stderr: read(stderr)
            )
        } catch {
            return ProcessResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }
    }

    private static func read(_ pipe: Pipe) -> String {
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
