import Foundation

public enum RuntimeActionEnvironmentError: LocalizedError {
    case invalidAdminPassword
    case adminPasswordFileCreateFailed

    public var errorDescription: String? {
        switch self {
        case .invalidAdminPassword:
            return "Admin password must be UTF-8."
        case .adminPasswordFileCreateFailed:
            return "Failed to prepare the admin password file."
        }
    }
}
