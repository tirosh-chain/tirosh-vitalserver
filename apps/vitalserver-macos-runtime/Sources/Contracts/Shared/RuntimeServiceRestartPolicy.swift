public struct RuntimeServiceRestartPolicy: Equatable, Sendable {
    public let restartVM: Bool
    public let restartGuestLogSync: Bool
    public let restartProxy: Bool
    public let restartWatchdog: Bool

    public init(
        restartVM: Bool,
        restartGuestLogSync: Bool,
        restartProxy: Bool,
        restartWatchdog: Bool
    ) {
        self.restartVM = restartVM
        self.restartGuestLogSync = restartGuestLogSync
        self.restartProxy = restartProxy
        self.restartWatchdog = restartWatchdog
    }

    public var anyServiceWasRunning: Bool {
        restartVM || restartGuestLogSync || restartProxy || restartWatchdog
    }
}
