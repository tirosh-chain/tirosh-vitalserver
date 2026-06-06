import Interfaces

typealias RuntimeLifecycleCommand = Interfaces.RuntimeLifecycleCommand
typealias RuntimeLifecycleCommandParseError = Interfaces.RuntimeLifecycleCommandParseError

extension RuntimeLifecycleCommand {
    static func parse(_ arguments: [String]) throws -> RuntimeLifecycleCommand {
        do {
            return try Interfaces.RuntimeLifecycleCommand.parseArguments(arguments)
        } catch RuntimeLifecycleCommandParseError.missingArgument(let message) {
            throw LauncherError.missingArgument(message)
        } catch RuntimeLifecycleCommandParseError.unsupportedCommand(let command) {
            throw LauncherError.unsupportedCommand(command)
        }
    }

    static var usage: String {
        Interfaces.RuntimeLifecycleCommand.usageText
    }
}
