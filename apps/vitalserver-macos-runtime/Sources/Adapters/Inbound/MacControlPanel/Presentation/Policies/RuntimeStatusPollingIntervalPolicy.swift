import RuntimeControl

public struct RuntimeStatusPollingIntervalPolicy {
    public static let activeOperationInterval: UInt64 = 1_000_000_000
    public static let steadyStateInterval: UInt64 = 5_000_000_000

    public init() {}

    public func statusPollingIntervalNanoseconds(status: RuntimeStatus) -> UInt64 {
        if RuntimeActiveOperationPolicy.isInstallInProgress(status)
            || RuntimeActiveOperationPolicy.isInitializationInProgress(status)
            || RuntimeActiveOperationPolicy.isUpdateInProgress(status)
            || RuntimeActiveOperationPolicy.isRecoveryInProgress(status)
            || status.runtimeState == .recovering {
            return Self.activeOperationInterval
        }
        return Self.steadyStateInterval
    }
}
