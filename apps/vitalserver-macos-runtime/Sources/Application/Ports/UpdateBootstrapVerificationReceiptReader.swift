import Contracts
import Foundation

public enum UpdateBootstrapVerificationReceiptReadResult: Equatable, Sendable {
    case missing(path: String)
    case loaded(UpdateBootstrapVerificationReceipt)
    case inspectionFailed(path: String, reason: String)
    case permissionDenied(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}

public protocol UpdateBootstrapVerificationReceiptReading {
    func read(
        at url: URL
    ) -> UpdateBootstrapVerificationReceiptReadResult
}
