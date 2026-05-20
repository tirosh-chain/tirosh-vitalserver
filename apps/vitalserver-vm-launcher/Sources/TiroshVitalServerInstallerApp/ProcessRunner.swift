import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var summary: String {
        let output = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum ProcessRunner {
    static func runSync(_ executable: String, arguments: [String]) -> ProcessResult {
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
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            )
        } catch {
            return ProcessResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
        }
    }

    static func run(_ executable: String, arguments: [String]) async -> ProcessResult {
        await Task.detached {
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
                return ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                    stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                )
            } catch {
                return ProcessResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
            }
        }.value
    }
}
