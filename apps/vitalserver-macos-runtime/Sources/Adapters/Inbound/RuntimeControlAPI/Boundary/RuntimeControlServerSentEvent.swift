import Contracts
import Errors
import Foundation
import RuntimeControl

public enum RuntimeControlServerSentEventCodec {
    public static let streamHeaders = [
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
    ]

    public static func encode<T: Encodable>(id: String, event: String, value: T) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        return try encode(RuntimeControlServerSentEvent(id: id, event: event, data: payload))
    }

    public static func encode(_ event: RuntimeControlServerSentEvent) throws -> Data {
        let text = try encodeString(event)
        return Data(text.utf8)
    }

    private static func encodeString(_ event: RuntimeControlServerSentEvent) throws -> String {
        if let comment = event.comment {
            return ": \(comment)\n\n"
        }
        guard let id = event.id, !id.isEmpty else {
            throw RuntimeControlServerSentEventEncodingError.missingID
        }
        guard let eventName = event.event, !eventName.isEmpty else {
            throw RuntimeControlServerSentEventEncodingError.missingEvent
        }
        guard let payload = event.data else {
            throw RuntimeControlServerSentEventEncodingError.missingData
        }
        guard let data = String(data: payload, encoding: .utf8) else {
            throw RuntimeControlServerSentEventEncodingError.invalidUTF8Data
        }
        return """
        id: \(id)
        event: \(eventName)
        data: \(data)

        """
    }
}

public struct RuntimeControlServerSentEvent: Equatable, Sendable {
    public let id: String?
    public let event: String?
    public let data: Data?
    public let comment: String?

    public init(id: String?, event: String?, data: Data? = nil, comment: String? = nil) {
        self.id = id
        self.event = event
        self.data = data
        self.comment = comment
    }

    public static let heartbeat = RuntimeControlServerSentEvent(id: nil, event: nil, comment: "heartbeat")

}
