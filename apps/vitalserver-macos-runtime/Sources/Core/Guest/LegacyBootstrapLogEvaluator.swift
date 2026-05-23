import Contracts
public enum LegacyBootstrapLogEvaluator {
    public static func failureReason(logContent: String, tailLineLimit: Int = 80) -> RuntimeFailureReason? {
        let tail = logContent
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(tailLineLimit)
            .joined(separator: "\n")
            .lowercased()
        if tail.contains("missing runtime package") {
            return .guestBootstrapMissingRuntimePackages
        }
        if tail.contains("error:") || tail.contains("failed") {
            return .guestBootstrapFailed
        }
        return nil
    }
}
