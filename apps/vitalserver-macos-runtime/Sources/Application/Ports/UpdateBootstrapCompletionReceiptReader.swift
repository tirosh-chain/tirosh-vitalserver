import Contracts
import Foundation

public enum UpdateBootstrapCompletionReceiptReadResult: Equatable, Sendable {
    case missing(path: String)
    case loaded(UpdateBootstrapCompletionReceipt)
    case inspectionFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}

public protocol UpdateBootstrapCompletionReceiptReading {
    func readCompletionReceipt(
        at url: URL
    ) -> UpdateBootstrapCompletionReceiptReadResult
}
