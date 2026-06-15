import Contracts

public struct RuntimeInstallStartOnBootPolicy {
    public init() {}

    public func sleepPreventionAction(
        startOnBoot: Bool,
        preventSystemSleep: Bool
    ) -> RuntimeInstallSleepPreventionBootAction {
        startOnBoot && preventSystemSleep ? .enable : .disable
    }
}
