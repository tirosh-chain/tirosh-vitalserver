import Contracts
import Errors

public enum GuestBootstrapAssessment: Equatable {
    case missing
    case unavailable(String)
    case notCurrentBoot
    case noFailure
    case failed(RuntimeFailureReason)
}

public enum GuestBootstrapEvaluator {
    public static func assess(_ result: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>) -> GuestBootstrapAssessment {
        switch result {
        case .missing:
            return .missing
        case .failed(let message):
            return .unavailable(message)
        case .loaded(let document):
            return assess(document)
        }
    }

    public static func assess(_ result: GuestBootstrapResultDocument) -> GuestBootstrapAssessment {
        switch result.status {
        case .running, .completed:
            return .noFailure
        case .failed:
            return .failed(result.reasonCodes?.first ?? .guestBootstrapFailed)
        case .unknown:
            return .failed(.guestBootstrapFailed)
        }
    }

    public static func failureReason(_ result: GuestBootstrapResultDocument) -> RuntimeFailureReason? {
        if case .failed(let reason) = assess(result) {
            return reason
        }
        return nil
    }
}
