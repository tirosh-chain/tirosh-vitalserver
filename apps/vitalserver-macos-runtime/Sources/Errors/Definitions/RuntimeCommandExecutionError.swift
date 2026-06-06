import Foundation

public enum RuntimeCommandExecutionError: Error, CustomStringConvertible, Equatable {
    case commandFailed(String)

    public var description: String {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}
