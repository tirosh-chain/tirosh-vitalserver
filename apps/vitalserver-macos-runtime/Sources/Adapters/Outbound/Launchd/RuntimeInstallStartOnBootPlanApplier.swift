import Contracts
import Errors

public struct RuntimeInstallStartOnBootPlanContext {
    public let launchctlExecutable: String

    public init(launchctlExecutable: String) {
        self.launchctlExecutable = launchctlExecutable
    }
}

public struct RuntimeInstallStartOnBootPlanOperations {
    public let setStartOnBoot: (Bool) throws -> Void
    public let runRequired: (String, [String]) throws -> Void

    public init(
        setStartOnBoot: @escaping (Bool) throws -> Void,
        runRequired: @escaping (String, [String]) throws -> Void
    ) {
        self.setStartOnBoot = setStartOnBoot
        self.runRequired = runRequired
    }
}

public struct RuntimeInstallStartOnBootPlanApplier {
    public let context: RuntimeInstallStartOnBootPlanContext
    public let operations: RuntimeInstallStartOnBootPlanOperations

    public init(
        context: RuntimeInstallStartOnBootPlanContext,
        operations: RuntimeInstallStartOnBootPlanOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func apply(plan: RuntimeInstallStartOnBootPlan) throws {
        try operations.setStartOnBoot(plan.startOnBoot)
        try operations.runRequired(
            context.launchctlExecutable,
            [plan.sleepPreventionAction.launchctlArgument, "system/\(RuntimeManagedService.sleepPrevention.label)"]
        )
    }
}

private extension RuntimeInstallSleepPreventionBootAction {
    var launchctlArgument: String {
        switch self {
        case .enable:
            return "enable"
        case .disable:
            return "disable"
        }
    }
}
