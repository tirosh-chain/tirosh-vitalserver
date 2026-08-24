import Contracts
import Foundation

/// The collected result of a completed child process whose stdout/stderr were
/// drained concurrently while it was still running, so large output cannot
/// block on a full pipe buffer.
public struct RuntimeProcessOutcome: Equatable, Sendable {
  public let exitCode: Int32
  public let terminationReason: Int
  public let stdout: String
  public let stderr: String
  public let outputIssues: [RuntimeCommandOutputIssue]
  public let executionIssue: String?

  public init(
    exitCode: Int32,
    terminationReason: Int,
    stdout: String,
    stderr: String,
    outputIssues: [RuntimeCommandOutputIssue],
    executionIssue: String?
  ) {
    self.exitCode = exitCode
    self.terminationReason = terminationReason
    self.stdout = stdout
    self.stderr = stderr
    self.outputIssues = outputIssues
    self.executionIssue = executionIssue
  }

  public var exitedNormally: Bool {
    terminationReason == Process.TerminationReason.exit.rawValue
      && executionIssue == nil
  }
}

/// Runs a child process and drains stdout/stderr concurrently, collecting the
/// final output only after the child has exited without a pipe-buffer race.
public struct RuntimeProcessOutputCollector {
  public init() {}

  public func run(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]? = nil,
    processFactory: @escaping () -> Process = Process.init
  ) -> RuntimeProcessOutcome {
    let process = processFactory()
    process.executableURL = executableURL
    process.arguments = arguments
    if let environment {
      process.environment = ProcessInfo.processInfo.environment.merging(
        environment
      ) { _, explicit in explicit }
    }
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    let drain = ConcurrentStreamDrain(stdout: stdoutPipe, stderr: stderrPipe)
    do {
      try process.run()
    } catch {
      process.standardOutput = nil
      process.standardError = nil
      try? stdoutPipe.fileHandleForReading.close()
      try? stdoutPipe.fileHandleForWriting.close()
      try? stderrPipe.fileHandleForReading.close()
      try? stderrPipe.fileHandleForWriting.close()
      return RuntimeProcessOutcome(
        exitCode: 1,
        terminationReason: Process.TerminationReason.exit.rawValue,
        stdout: "",
        stderr: "",
        outputIssues: [],
        executionIssue: String(describing: error)
      )
    }
    try? stdoutPipe.fileHandleForWriting.close()
    try? stderrPipe.fileHandleForWriting.close()
    drain.start()
    process.waitUntilExit()
    let captured = drain.capturedOutput()
    return RuntimeProcessOutcome(
      exitCode: process.terminationStatus,
      terminationReason: process.terminationReason.rawValue,
      stdout: captured.stdout,
      stderr: captured.stderr,
      outputIssues: captured.outputIssues,
      executionIssue: nil
    )
  }
}

private final class ConcurrentStreamDrain: @unchecked Sendable {
  private let stdout: Pipe
  private let stderr: Pipe
  private let readers = DispatchGroup()
  private let lock = NSLock()
  private var stdoutData = Data()
  private var stderrData = Data()

  init(stdout: Pipe, stderr: Pipe) {
    self.stdout = stdout
    self.stderr = stderr
  }

  func start() {
    startReader(for: .stdout)
    startReader(for: .stderr)
  }

  func capturedOutput() -> (
    stdout: String,
    stderr: String,
    outputIssues: [RuntimeCommandOutputIssue]
  ) {
    readers.wait()

    lock.lock()
    defer { lock.unlock() }
    let stdout = decodeOutput(stdoutData, stream: .stdout)
    let stderr = decodeOutput(stderrData, stream: .stderr)
    return (
      stdout: stdout.text,
      stderr: stderr.text,
      outputIssues: [stdout.issue, stderr.issue].compactMap { $0 }
    )
  }

  private func startReader(for stream: OutputStream) {
    readers.enter()
    DispatchQueue.global(qos: .utility).async { [self] in
      defer { readers.leave() }
      let handle: FileHandle
      switch stream {
      case .stdout:
        handle = stdout.fileHandleForReading
      case .stderr:
        handle = stderr.fileHandleForReading
      }
      let data = handle.readDataToEndOfFile()
      try? handle.close()
      append(data, stream: stream)
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
