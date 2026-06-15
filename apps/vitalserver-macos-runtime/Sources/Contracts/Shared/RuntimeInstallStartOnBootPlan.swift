public enum RuntimeInstallSleepPreventionBootAction: Equatable, Sendable {
    case enable
    case disable
}

public struct RuntimeInstallStartOnBootPlan: Equatable, Sendable {
    public let startOnBoot: Bool
    public let sleepPreventionAction: RuntimeInstallSleepPreventionBootAction

    public init(
        startOnBoot: Bool,
        sleepPreventionAction: RuntimeInstallSleepPreventionBootAction
    ) {
        self.startOnBoot = startOnBoot
        self.sleepPreventionAction = sleepPreventionAction
    }
}
