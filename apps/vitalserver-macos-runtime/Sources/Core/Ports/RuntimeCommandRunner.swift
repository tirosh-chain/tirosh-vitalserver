import Contracts
import Foundation

public struct RuntimeProcessResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol RuntimeCommandRunner {
    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult
    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult
}
