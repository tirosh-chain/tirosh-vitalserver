import Contracts
import Foundation

public enum GuestBootstrapAssessment: Equatable {
    case missing
    case unavailable(String)
    case notCurrentBoot
    case noFailure
    case failed(RuntimeFailureReason)
}

public enum GuestBootstrapEvaluator {
    public static func assessCurrentBoot(
        _ result: RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>,
        guestState: GuestRuntimeStateDocument?,
        now: Date,
        graceSeconds: TimeInterval
    ) -> GuestBootstrapAssessment {
        switch result {
        case .missing, .failed:
            return assess(result)
        case .loaded(let document):
            guard resultBelongsToCurrentBoot(
                document,
                guestState: guestState,
                now: now,
                graceSeconds: graceSeconds
            ) else {
                return .notCurrentBoot
            }
            return assess(document)
        }
    }

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

    private static func resultBelongsToCurrentBoot(
        _ result: GuestBootstrapResultDocument,
        guestState: GuestRuntimeStateDocument?,
        now: Date,
        graceSeconds: TimeInterval
    ) -> Bool {
        guard let bootstrapBootID = nonEmpty(result.bootID) else {
            return false
        }
        guard let guestBootID = nonEmpty(guestState?.bootID) else {
            return isFresh(result, now: now, graceSeconds: graceSeconds)
        }
        return bootstrapBootID == guestBootID
    }

    private static func isFresh(
        _ result: GuestBootstrapResultDocument,
        now: Date,
        graceSeconds: TimeInterval
    ) -> Bool {
        guard let updatedAt = result.updatedAt,
              let updatedAtDate = ISO8601DateFormatter().date(from: updatedAt)
        else {
            return false
        }
        return now.timeIntervalSince(updatedAtDate) <= graceSeconds
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}
