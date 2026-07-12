import Foundation
import RuntimeControl

public struct RuntimeControlErrorResponse: Codable, Equatable, Sendable {
    public let code: RuntimeControlAPIErrorCode
    public let message: String

    public init(code: RuntimeControlAPIErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

enum RuntimeControlHTTPErrorResponseMapper {
    static func response(for error: Error) -> RuntimeControlHTTPResponse {
        if let queryError = error as? RuntimeControlHTTPQueryError {
            return RuntimeControlHTTPResponseFactory.error(
                status: .badRequest,
                code: .badRequest,
                message: queryError.localizedDescription
            )
        }
        if let operationConflict = error as? RuntimeControlOperationInProgressError {
            return RuntimeControlHTTPResponseFactory.error(
                status: .conflict,
                code: .operationInProgress,
                message: operationConflict.message
            )
        }
        if let handlerError = error as? RuntimeControlAPIReadHandlerError {
            return response(for: handlerError)
        }
        return RuntimeControlHTTPResponseFactory.error(
            status: .internalServerError,
            code: .handlerFailed,
            message: error.localizedDescription
        )
    }

    private static func response(for error: RuntimeControlAPIReadHandlerError) -> RuntimeControlHTTPResponse {
        switch error {
        case .platformAffordanceUnavailable, .runtimeProviderControlUnavailable:
            return RuntimeControlHTTPResponseFactory.error(
                status: .notImplemented,
                code: .platformAffordanceUnavailable,
                message: error.localizedDescription
            )
        case .unsupportedFileReference:
            return RuntimeControlHTTPResponseFactory.error(
                status: .badRequest,
                code: .badRequest,
                message: error.localizedDescription
            )
        }
    }
}

public enum RuntimeControlErrorResponseEncoder {
    public static func encode(code: RuntimeControlAPIErrorCode, message: String) -> Data {
        Data("{\"code\":\"\(jsonStringContent(code.rawValue))\",\"message\":\"\(jsonStringContent(message))\"}".utf8)
    }

    private static func jsonStringContent(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\u{08}":
                result += "\\b"
            case "\u{0C}":
                result += "\\f"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            case let control where control.value < 0x20:
                result += String(format: "\\u%04X", control.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
