import Foundation

public enum RuntimeLifecycleCommandParseError: Error, Equatable {
    case missingArgument(String)
    case unsupportedCommand(String)
}
