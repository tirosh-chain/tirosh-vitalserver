import Foundation

public enum RuntimeViewModelError: LocalizedError {
    case invalidAdminPassword
    case adminPasswordFileCreateFailed

    public var errorDescription: String? {
        switch self {
        case .invalidAdminPassword:
            return "Admin password reset value is invalid."
        case .adminPasswordFileCreateFailed:
            return "Could not prepare admin password reset file."
        }
    }
}
