import Foundation
import RuntimeCore
import RuntimeContracts
import HostRuntimeInfrastructure

struct SystemRuntimeCommandRunner: RuntimeCommandRunner {
    private let fileStore: RuntimeFileWriting

    init(fileStore: RuntimeFileWriting = LocalRuntimeFileStore()) {
        self.fileStore = fileStore
    }

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
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
            return RuntimeProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: output, encoding: .utf8) ?? "",
                stderr: String(data: errorOutput, encoding: .utf8) ?? ""
            )
        } catch {
            return RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        let process = Process()
        let stderr = Pipe()

        do {
            try fileStore.writeData(Data(), to: output, options: [])
            let outputHandle = try FileHandle(forWritingTo: output)
            defer {
                try? outputHandle.close()
            }
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputHandle
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
            return RuntimeProcessResult(
                exitCode: process.terminationStatus,
                stdout: "",
                stderr: String(data: errorOutput, encoding: .utf8) ?? ""
            )
        } catch {
            return RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
    }
}
