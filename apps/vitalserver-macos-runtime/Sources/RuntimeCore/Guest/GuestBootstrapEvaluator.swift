import RuntimeContracts
public enum GuestBootstrapEvaluator {
    public static func failureReason(_ result: GuestBootstrapResultDocument?) -> RuntimeFailureReason? {
        guard let result else {
            return nil
        }

        switch result.status {
        case .running, .completed:
            return nil
        case .failed:
            return result.reasonCodes?.first ?? .guestBootstrapFailed
        case .unknown:
            return .guestBootstrapFailed
        }
    }
}
