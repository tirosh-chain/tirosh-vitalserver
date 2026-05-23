import Foundation
import RuntimeControl

enum ProcessRunner {
    static func run(_ executable: String, arguments: [String]) async -> RuntimeCommandResult {
        await Task.detached {
            runSync(executable, arguments: arguments)
        }.value
    }

    static func runSync(_ executable: String, arguments: [String]) -> RuntimeCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let output = ProcessOutputCollector(stdout: stdout, stderr: stderr)
        output.start()
        defer { output.stop() }

        do {
            try process.run()
            process.waitUntilExit()
            let captured = output.capturedOutput()
            return RuntimeCommandResult(
                exitCode: process.terminationStatus,
                stdout: captured.stdout,
                stderr: captured.stderr
            )
        } catch {
            return RuntimeCommandResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }
    }
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let stdout: Pipe
    private let stderr: Pipe
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    init(stdout: Pipe, stderr: Pipe) {
        self.stdout = stdout
        self.stderr = stderr
    }

    func start() {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, stream: .stdout)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, stream: .stderr)
        }
    }

    func stop() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
    }

    func capturedOutput() -> (stdout: String, stderr: String) {
        drain(stdout.fileHandleForReading, stream: .stdout)
        drain(stderr.fileHandleForReading, stream: .stderr)

        lock.lock()
        defer { lock.unlock() }
        return (
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private func drain(_ handle: FileHandle, stream: OutputStream) {
        let data = handle.availableData
        append(data, stream: stream)
    }

    private func append(_ data: Data, stream: OutputStream) {
        guard !data.isEmpty else {
            return
        }
        lock.lock()
        switch stream {
        case .stdout:
            stdoutData.append(data)
        case .stderr:
            stderrData.append(data)
        }
        lock.unlock()
    }

    private enum OutputStream {
        case stdout
        case stderr
    }
}
