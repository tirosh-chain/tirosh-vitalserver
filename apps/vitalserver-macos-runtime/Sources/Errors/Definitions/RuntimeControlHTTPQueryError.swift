import Foundation

public enum RuntimeControlHTTPQueryError: LocalizedError, Equatable {
    case invalidLimit(String)
    case invalidCursor(String)
    case invalidEventType(String)
    case invalidLogSource(String)
    case duplicateQueryParameter(String)
    case missingQueryParameterValue(String)
    case invalidPathParameter(String)
    case missingBody
    case invalidBody(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let value):
            return "Invalid runtime event limit: \(value)"
        case .invalidCursor(let value):
            return "Invalid runtime event cursor: \(value)"
        case .invalidEventType(let value):
            return "Invalid runtime event type: \(value)"
        case .invalidLogSource(let value):
            return "Invalid runtime log source: \(value)"
        case .duplicateQueryParameter(let name):
            return "Duplicate query parameter: \(name)"
        case .missingQueryParameterValue(let name):
            return "Missing query parameter value: \(name)"
        case .invalidPathParameter(let name):
            return "Invalid path parameter: \(name)"
        case .missingBody:
            return "Missing request body."
        case .invalidBody(let message):
            return "Invalid request body: \(message)"
        }
    }
}
