import Contracts
import Domain

public enum SettleUpdateBootstrapHandoffError: Error, Equatable, Sendable {
    case receiptMissing(path: String)
    case receiptInspectionFailed(path: String, reason: String)
    case receiptReadFailed(path: String, reason: String)
    case receiptDecodeFailed(path: String, reason: String)
    case receiptPathStateInvalid(path: String, state: String)
}

public struct SettleUpdateBootstrapHandoffUseCase {
    public init() {}

    public func execute(
        journal: UpdateBootstrapJournal,
        receiptRead: UpdateBootstrapCompletionReceiptReadResult
    ) throws -> UpdateBootstrapJournal {
        switch receiptRead {
        case .loaded(let receipt):
            return try UpdateBootstrapJournalStateMachine.transition(
                journal: journal,
                event: .completed(receipt)
            )
        case .missing(let path):
            throw SettleUpdateBootstrapHandoffError.receiptMissing(path: path)
        case .inspectionFailed(let path, let reason):
            throw SettleUpdateBootstrapHandoffError.receiptInspectionFailed(
                path: path,
                reason: reason
            )
        case .readFailed(let path, let reason):
            throw SettleUpdateBootstrapHandoffError.receiptReadFailed(
                path: path,
                reason: reason
            )
        case .decodeFailed(let path, let reason):
            throw SettleUpdateBootstrapHandoffError.receiptDecodeFailed(
                path: path,
                reason: reason
            )
        case .unexpectedPathState(let path, let state):
            throw SettleUpdateBootstrapHandoffError.receiptPathStateInvalid(
                path: path,
                state: state
            )
        }
    }
}
