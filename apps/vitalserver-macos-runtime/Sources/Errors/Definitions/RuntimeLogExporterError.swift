import Foundation

public enum RuntimeLogExporterError: LocalizedError, Equatable {
    case missingPOSIXPermissions(path: String)

    public var errorDescription: String? {
        switch self {
        case .missingPOSIXPermissions(let path):
            return "POSIX permissions are missing for \(path)"
        }
    }
}
