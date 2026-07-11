import Contracts
import Foundation
import RuntimeControl

enum RuntimeControlHTTPResponseFactory {
    static func json<T: Encodable>(
        _ value: T,
        status: RuntimeControlHTTPStatus = .ok
    ) throws -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(value)
        )
    }

    static func eventStream<T: Encodable>(
        id: String,
        event: String,
        value: T
    ) throws -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .ok,
            headers: RuntimeControlServerSentEventCodec.streamHeaders,
            body: try RuntimeControlServerSentEventCodec.encode(id: id, event: event, value: value)
        )
    }

    static func streamSnapshot(_ stream: RuntimeControlHTTPStreamResponse) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: stream.status,
            headers: stream.headers,
            body: nil
        )
    }

    static func error(
        status: RuntimeControlHTTPStatus,
        code: RuntimeControlAPIErrorCode,
        message: String
    ) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json"],
            body: RuntimeControlErrorResponseEncoder.encode(code: code, message: message)
        )
    }

    static func resourceNotFound(_ message: String) -> RuntimeControlHTTPResponse {
        error(status: .notFound, code: .resourceNotFound, message: message)
    }
}
