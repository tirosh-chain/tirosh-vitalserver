import Contracts
import Foundation

public typealias RuntimeProcessResult = Contracts.RuntimeProcessResult

public protocol RuntimeCommandRunner {
    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult
    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult
}
