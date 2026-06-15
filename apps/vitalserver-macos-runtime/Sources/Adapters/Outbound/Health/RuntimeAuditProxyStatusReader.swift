import Application
import Contracts
import Foundation
import Errors

public struct RuntimeAuditProxyStatusReader {
    private let curlPath: String
    private let commandRunner: RuntimeCommandRunner
    private let statusURL: (Int) -> String

    public init(
        curlPath: String,
        commandRunner: RuntimeCommandRunner,
        statusURL: @escaping (Int) -> String
    ) {
        self.curlPath = curlPath
        self.commandRunner = commandRunner
        self.statusURL = statusURL
    }

    public func read(port: Int) -> RuntimeAuditProxyStatusReadResult {
        let result = commandRunner.run(
            curlPath,
            arguments: ["-fsS", "--max-time", "5", statusURL(port)]
        )
        if !result.outputIssues.isEmpty {
            return RuntimeAuditProxyStatusReadResult(
                readState: .outputInvalid,
                httpStatus: RuntimeHTTPStatusText.invalidResponse,
                document: nil,
                readError: "output-invalid \(RuntimeProcessFailureMessageFormatter.message(result))"
            )
        }
        guard result.exitCode == 0 else {
            return RuntimeAuditProxyStatusReadResult(
                readState: .commandFailed,
                httpStatus: RuntimeHTTPStatusText.failed,
                document: nil,
                readError: "command-failed-\(result.exitCode) \(RuntimeProcessFailureMessageFormatter.message(result))"
            )
        }
        guard !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RuntimeAuditProxyStatusReadResult(
                readState: .emptyResponse,
                httpStatus: RuntimeHTTPStatusText.invalidResponse,
                document: nil,
                readError: "empty-response"
            )
        }
        do {
            let document = try JSONDecoder().decode(
                RuntimeAuditProxyStatusDocument.self,
                from: Data(result.stdout.utf8)
            )
            return RuntimeAuditProxyStatusReadResult(
                readState: .loaded,
                httpStatus: "200",
                document: document,
                readError: nil
            )
        } catch {
            return RuntimeAuditProxyStatusReadResult(
                readState: .invalidResponse,
                httpStatus: RuntimeHTTPStatusText.invalidResponse,
                document: nil,
                readError: "decode-failed reason=\(String(describing: error))"
            )
        }
    }
}
