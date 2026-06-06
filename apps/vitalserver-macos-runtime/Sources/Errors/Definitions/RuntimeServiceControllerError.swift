import Foundation

public enum RuntimeServiceControllerError: Error, CustomStringConvertible, Equatable {
    case runtimeOperationFailed(String)
    case missingArgument(String)

    public var description: String {
        switch self {
        case .runtimeOperationFailed(let message), .missingArgument(let message):
            return message
        }
    }
}
