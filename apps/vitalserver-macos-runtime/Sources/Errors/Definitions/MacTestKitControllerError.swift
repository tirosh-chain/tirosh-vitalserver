import Foundation

public enum MacTestKitControllerError: LocalizedError, Equatable {
    case apiEndpointUnavailable(String)
    case apiUnavailable(String)
    case invalidResponse
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .apiEndpointUnavailable(let message):
            return message
        case .apiUnavailable(let apiBaseURL):
            return "TestKit container API is not reachable at \(apiBaseURL)."
        case .invalidResponse:
            return "TestKit API returned an invalid response."
        case .requestFailed(let message):
            return message
        }
    }
}
