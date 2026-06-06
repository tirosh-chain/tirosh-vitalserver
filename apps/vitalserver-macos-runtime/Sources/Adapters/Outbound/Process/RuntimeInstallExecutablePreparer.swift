import Errors
public struct RuntimeInstallExecutablePreparationContext: Equatable, Sendable {
    public let executablePaths: [String]
    public let chmodExecutable: String

    public init(
        executablePaths: [String],
        chmodExecutable: String
    ) {
        self.executablePaths = executablePaths
        self.chmodExecutable = chmodExecutable
    }
}

public struct RuntimeInstallExecutablePreparationOperations {
    public let runRequired: (String, [String]) throws -> Void

    public init(runRequired: @escaping (String, [String]) throws -> Void) {
        self.runRequired = runRequired
    }
}

public struct RuntimeInstallExecutablePreparer {
    public let context: RuntimeInstallExecutablePreparationContext
    public let operations: RuntimeInstallExecutablePreparationOperations

    public init(
        context: RuntimeInstallExecutablePreparationContext,
        operations: RuntimeInstallExecutablePreparationOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func prepare() throws {
        for path in context.executablePaths {
            try operations.runRequired(context.chmodExecutable, ["0755", path])
        }
    }
}
