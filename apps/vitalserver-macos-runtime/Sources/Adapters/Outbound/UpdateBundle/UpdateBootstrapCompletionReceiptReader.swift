import Application
import Contracts
import Foundation

public struct UpdateBootstrapCompletionReceiptReader:
    UpdateBootstrapCompletionReceiptReading
{
    public let pathState: (URL) -> RuntimePathState
    public let readData: (URL) throws -> Data

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        readData: @escaping (URL) throws -> Data
    ) {
        self.pathState = pathState
        self.readData = readData
    }

    public func readCompletionReceipt(
        at url: URL
    ) -> UpdateBootstrapCompletionReceiptReadResult {
        switch pathState(url) {
        case .missing:
            return .missing(path: url.path)
        case .file:
            break
        case .directory:
            return .unexpectedPathState(path: url.path, state: "directory")
        case .other(let value):
            return .unexpectedPathState(path: url.path, state: value)
        case .inspectFailed(let reason):
            return .inspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            return .unexpectedPathState(path: url.path, state: value)
        }

        let data: Data
        do {
            data = try readData(url)
        } catch {
            return .readFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
        do {
            return .loaded(
                try JSONDecoder().decode(
                    UpdateBootstrapCompletionReceipt.self,
                    from: data
                )
            )
        } catch {
            return .decodeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }
}
