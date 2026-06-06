import Foundation

public enum RuntimeControlServerSentEventEncodingError: LocalizedError, Equatable, Sendable {
    case missingID
    case missingEvent
    case missingData
    case invalidUTF8Data

    public var errorDescription: String? {
        switch self {
        case .missingID:
            return "SSE event id is missing."
        case .missingEvent:
            return "SSE event name is missing."
        case .missingData:
            return "SSE event data is missing."
        case .invalidUTF8Data:
            return "SSE event data is not valid UTF-8."
        }
    }
}
