import Foundation

public enum RuntimeHostFileReaderError: LocalizedError, Equatable {
    case invalidUTF8(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8(let path):
            return "Log file is not valid UTF-8: \(path)"
        }
    }
}
