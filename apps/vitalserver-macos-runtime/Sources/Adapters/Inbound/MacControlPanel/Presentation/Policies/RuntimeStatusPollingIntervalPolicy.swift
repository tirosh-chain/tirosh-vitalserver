import RuntimeControl

public struct RuntimeStatusPollingIntervalPolicy {
    public static let activeOperationInterval: UInt64 = 1_000_000_000
    public static let steadyStateInterval: UInt64 = 5_000_000_000

    public init() {}

    public func statusPollingIntervalNanoseconds(
        status: PlatformState,
        operationState: PlatformOperationState
    ) -> UInt64 {
        if operationState.hasActiveOperation || status.platformHealth == .recovering {
            return Self.activeOperationInterval
        }
        return Self.steadyStateInterval
    }

}
