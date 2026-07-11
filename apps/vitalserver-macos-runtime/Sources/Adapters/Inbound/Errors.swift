import Foundation


public enum RuntimeControlAPIReadHandlerError: LocalizedError, Equatable {
    case platformAffordanceUnavailable
    case unsupportedFileReference(String)

    public var errorDescription: String? {
        switch self {
        case .platformAffordanceUnavailable:
            return "Host affordance client is unavailable."
        case .unsupportedFileReference(let kind):
            return "File reference kind \(kind) is not supported by this local Runtime Control handler."
        }
    }
}


public enum RuntimeControlHTTPQueryError: LocalizedError, Equatable {
    case invalidLimit(String)
    case invalidCursor(String)
    case invalidEventType(String)
    case invalidLogSource(String)
    case invalidQueryParameter(String, String)
    case invalidQueryString(String)
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
        case .invalidQueryParameter(let name, let value):
            return "Invalid query parameter \(name): \(value)"
        case .invalidQueryString(let value):
            return "Invalid query string: \(value)"
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


public enum RuntimeControlHTTPWireCodecError: Error, Equatable {
    case invalidRequest
    case unsupportedMethod(String)
    case invalidContentLength(String)
}


public enum RuntimeControlLocalHTTPServerError: Error, Equatable {
    case invalidPort(UInt16)
    case listenerUnavailable
}


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


public enum RuntimeHealthCheckRunnerError: Error, CustomStringConvertible, Equatable {
    case runtimeHealthFailed

    public var description: String {
        switch self {
        case .runtimeHealthFailed:
            return "runtime health check failed"
        }
    }
}


public enum RuntimeInstallSettingsError: Error, Equatable {
    case missingArgument(String)
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}


public enum RuntimeLifecycleCommandParseError: Error, Equatable {
    case missingArgument(String)
    case unsupportedCommand(String)
}
