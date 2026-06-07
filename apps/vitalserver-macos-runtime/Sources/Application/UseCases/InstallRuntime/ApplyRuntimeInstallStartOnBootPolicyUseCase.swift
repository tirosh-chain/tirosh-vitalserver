import Contracts
import Domain

public struct RuntimeInstallStartOnBootPolicyInput: Equatable, Sendable {
    public let startOnBoot: Bool
    public let preventSystemSleep: Bool

    public init(
        startOnBoot: Bool,
        preventSystemSleep: Bool
    ) {
        self.startOnBoot = startOnBoot
        self.preventSystemSleep = preventSystemSleep
    }
}

public struct ApplyRuntimeInstallStartOnBootPolicyUseCase {
    public init() {}

    public func plan(input: RuntimeInstallStartOnBootPolicyInput) -> RuntimeInstallStartOnBootPlan {
        RuntimeInstallStartOnBootPlan(
            startOnBoot: input.startOnBoot,
            sleepPreventionAction: RuntimeInstallStartOnBootPolicy().sleepPreventionAction(
                startOnBoot: input.startOnBoot,
                preventSystemSleep: input.preventSystemSleep
            )
        )
    }
}
