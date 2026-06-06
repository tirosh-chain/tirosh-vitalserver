import Foundation

public enum RuntimeControlAPIReadHandlerError: LocalizedError, Equatable {
    case hostAffordanceUnavailable
    case unsupportedFileReference(String)

    public var errorDescription: String? {
        switch self {
        case .hostAffordanceUnavailable:
            return "Host affordance client is unavailable."
        case .unsupportedFileReference(let kind):
            return "File reference kind \(kind) is not supported by this local Runtime Control handler."
        }
    }
}
