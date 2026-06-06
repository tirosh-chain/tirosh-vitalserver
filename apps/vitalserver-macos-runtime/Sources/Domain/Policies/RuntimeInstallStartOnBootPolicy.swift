import Errors
public enum RuntimeInstallSleepPreventionBootAction: Equatable, Sendable {
    case enable
    case disable
}

public struct RuntimeInstallStartOnBootPolicy {
    public init() {}

    public func sleepPreventionAction(
        startOnBoot: Bool,
        preventSystemSleep: Bool
    ) -> RuntimeInstallSleepPreventionBootAction {
        startOnBoot && preventSystemSleep ? .enable : .disable
    }
}
