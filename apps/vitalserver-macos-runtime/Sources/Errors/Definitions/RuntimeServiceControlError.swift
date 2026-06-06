import Foundation

public enum RuntimeServiceControlError: Error, Equatable {
    case operationFailed(String)
}
