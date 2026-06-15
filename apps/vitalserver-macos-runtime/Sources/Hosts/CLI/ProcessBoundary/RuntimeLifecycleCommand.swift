import InboundAdapters
import Errors

extension RuntimeLifecycleCommand {
    static func parse(_ arguments: [String]) throws -> RuntimeLifecycleCommand {
        do {
            return try InboundAdapters.RuntimeLifecycleCommand.parseArguments(arguments)
        } catch RuntimeLifecycleCommandParseError.missingArgument(let message) {
            throw LauncherError.missingArgument(message)
        } catch RuntimeLifecycleCommandParseError.unsupportedCommand(let command) {
            throw LauncherError.unsupportedCommand(command)
        }
    }

    static var usage: String {
        InboundAdapters.RuntimeLifecycleCommand.usageText
    }
}
