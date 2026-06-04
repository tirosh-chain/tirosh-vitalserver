import Contracts

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

public struct RuntimeInstallStartOnBootPolicyContext {
    public let launchctlExecutable: String

    public init(launchctlExecutable: String) {
        self.launchctlExecutable = launchctlExecutable
    }
}

public struct RuntimeInstallStartOnBootPolicyOperations {
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

public struct RuntimeInstallStartOnBootPolicyApplier {
    public let context: RuntimeInstallStartOnBootPolicyContext
    public let operations: RuntimeInstallStartOnBootPolicyOperations

    public init(
        context: RuntimeInstallStartOnBootPolicyContext,
        operations: RuntimeInstallStartOnBootPolicyOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func apply(input: RuntimeInstallStartOnBootPolicyInput) throws {
        try operations.setStartOnBoot(input.startOnBoot)
        let action = input.preventSystemSleep && input.startOnBoot ? "enable" : "disable"
        try operations.runRequired(
            context.launchctlExecutable,
            [action, "system/\(RuntimeManagedService.sleepPrevention.label)"]
        )
    }
}
