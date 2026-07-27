import Application
import Contracts
import Foundation

public struct UpdateBootstrapCompletionReportReader:
    UpdateBootstrapCompletionReportReading,
    @unchecked Sendable
{
    public let pathState: (URL) -> RuntimePathState
    public let readData: (URL) throws -> Data
    public let sha256: (Data) -> String

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        readData: @escaping (URL) throws -> Data,
        sha256: @escaping (Data) -> String
    ) {
        self.pathState = pathState
        self.readData = readData
        self.sha256 = sha256
    }

    public func readCompletionReport(
        relativePath: String,
        beneath stagedRoot: URL
    ) -> UpdateBootstrapCompletionReportReadResult {
        let url = stagedRoot.appendingPathComponent(relativePath)
        switch pathState(url) {
        case .missing:
            return .missing(path: relativePath)
        case .file:
            break
        case .directory:
            return .unexpectedPathState(
                path: relativePath,
                state: "directory"
            )
        case .other(let value):
            return .unexpectedPathState(
                path: relativePath,
                state: value
            )
        case .inspectFailed(let reason):
            return .inspectionFailed(
                path: relativePath,
                reason: reason
            )
        case .unknown(let value):
            return .unexpectedPathState(
                path: relativePath,
                state: value
            )
        }
        do {
            return .loaded(
                path: relativePath,
                sha256: sha256(try readData(url))
            )
        } catch {
            return .readFailed(
                path: relativePath,
                reason: String(describing: error)
            )
        }
    }
}
