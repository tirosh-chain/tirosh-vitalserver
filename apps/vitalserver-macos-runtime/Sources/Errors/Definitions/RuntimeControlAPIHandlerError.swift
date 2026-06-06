import Foundation

public enum RuntimeControlAPIHandlerError: LocalizedError, Equatable {
    case unsupportedFileReference(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileReference(let kind):
            return "File reference kind \(kind) is not supported by this local Runtime Control handler."
        }
    }
}
