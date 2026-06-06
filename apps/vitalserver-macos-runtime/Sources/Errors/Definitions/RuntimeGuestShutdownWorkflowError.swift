import Foundation

public enum RuntimeGuestShutdownWorkflowError: Error, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}
