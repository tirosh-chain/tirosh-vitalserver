import Foundation

public enum RuntimeHealthWaitUseCaseError: Error, Equatable, CustomStringConvertible {
    case operationFailed(String)

    public var description: String {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}
