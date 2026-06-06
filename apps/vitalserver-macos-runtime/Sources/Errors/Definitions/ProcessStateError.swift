import Foundation

public enum ProcessStateError: Error, CustomStringConvertible, Equatable {
    case runtimeOperationFailed(String)

    public var description: String {
        switch self {
        case .runtimeOperationFailed(let message):
            return message
        }
    }
}
