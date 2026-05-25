import Foundation
import RuntimeControl
import Core
import Contracts

public enum RuntimeControlHTTPStatus: Int, Codable, Equatable, Sendable {
    case ok = 200
    case badRequest = 400
    case unauthorized = 401
    case notFound = 404
    case methodNotAllowed = 405
    case notImplemented = 501
    case internalServerError = 500
}

public struct RuntimeControlHTTPRequest: Equatable, Sendable {
    public let method: RuntimeControlHTTPMethod
    public let path: String
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: RuntimeControlHTTPMethod,
        path: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct RuntimeControlHTTPResponse: Equatable, Sendable {
    public let status: RuntimeControlHTTPStatus
    public let headers: [String: String]
    public let body: Data?

    public init(
        status: RuntimeControlHTTPStatus,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public struct RuntimeControlHTTPStreamResponse: Sendable {
    public let status: RuntimeControlHTTPStatus
    public let headers: [String: String]
    public let events: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>

    public init(
        status: RuntimeControlHTTPStatus,
        headers: [String: String],
        events: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>
    ) {
        self.status = status
        self.headers = headers
        self.events = events
    }
}

public enum RuntimeControlHTTPRouteResult: Sendable {
    case response(RuntimeControlHTTPResponse)
    case stream(RuntimeControlHTTPStreamResponse)
}

public struct RuntimeControlAPIStreamConfiguration: Equatable, Sendable {
    public let pollIntervalNanoseconds: UInt64
    public let heartbeatIntervalNanoseconds: UInt64

    public init(
        pollIntervalNanoseconds: UInt64 = 1_000_000_000,
        heartbeatIntervalNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.heartbeatIntervalNanoseconds = heartbeatIntervalNanoseconds
    }
}

@MainActor
public protocol RuntimeControlAPIReadHandler {
    func loadCapabilities() async throws -> RuntimeControlCapabilities
    func loadStatus() async throws -> RuntimeStatus
    func loadEvents(query: RuntimeEventQuery) async throws -> RuntimeEventHistory
    func loadVitalDBObservation() async throws -> VitalDBObservationDocument?
    func loadHealthStatus() async throws -> RuntimeStatus
    func loadSettings() async throws -> RuntimeSettings
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo
    func loadInstallInfo() async throws -> RuntimeInstallInfo
    func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse
}

@MainActor
public struct RuntimeControlAPIRouter {
    private let handler: any RuntimeControlAPIReadHandler
    private let authorization: RuntimeControlAPIAuthorization?
    private let streamConfiguration: RuntimeControlAPIStreamConfiguration

    public init(
        handler: any RuntimeControlAPIReadHandler,
        authorization: RuntimeControlAPIAuthorization? = nil,
        streamConfiguration: RuntimeControlAPIStreamConfiguration = RuntimeControlAPIStreamConfiguration()
    ) {
        self.handler = handler
        self.authorization = authorization
        self.streamConfiguration = streamConfiguration
    }

    public func routeResult(_ request: RuntimeControlHTTPRequest) async -> RuntimeControlHTTPRouteResult {
        if let authorization, !authorization.allows(request: request) {
            return .response(errorResponse(
                status: .unauthorized,
                code: .unauthorized,
                message: "Runtime Control token is missing or invalid."
            ))
        }

        if let endpoint = RuntimeControlAPIEndpoint.matching(method: request.method, path: request.path) {
            if let stream = streamResponse(endpoint, request: request) {
                return .stream(stream)
            }
            return .response(await route(endpoint, request: request))
        }

        guard RuntimeControlAPIEndpoint.matching(path: request.path) != nil else {
            return .response(errorResponse(status: .notFound, code: .routeNotFound, message: "Route not found."))
        }

        return .response(errorResponse(
            status: .methodNotAllowed,
            code: .methodNotAllowed,
            message: "Method is not allowed for this route."
        ))
    }

    public func route(_ request: RuntimeControlHTTPRequest) async -> RuntimeControlHTTPResponse {
        switch await routeResult(request) {
        case .response(let response):
            return response
        case .stream(let stream):
            return streamSnapshotResponse(stream)
        }
    }

    private func route(_ endpoint: RuntimeControlAPIEndpoint, request: RuntimeControlHTTPRequest) async -> RuntimeControlHTTPResponse {
        do {
            switch endpoint {
            case .capabilities:
                return try await jsonResponse(handler.loadCapabilities())
            case .status:
                return try await jsonResponse(handler.loadStatus())
            case .statusStream:
                return try await eventStreamResponse(
                    id: "runtime-status",
                    event: "runtime-status",
                    value: handler.loadStatus()
                )
            case .events:
                let query = try request.runtimeEventQuery()
                return try await jsonResponse(handler.loadEvents(query: query))
            case .eventStream:
                let query = try request.runtimeEventQuery()
                return try await eventStreamResponse(handler.loadEvents(query: query))
            case .vitalDBObservation:
                return try await jsonResponse(handler.loadVitalDBObservation())
            case .vitalDBObservationStream:
                return try await eventStreamResponse(
                    id: "vitaldb-observation",
                    event: "vitaldb-observed",
                    value: handler.loadVitalDBObservation()
                )
            case .health:
                return try await jsonResponse(handler.loadHealthStatus())
            case .settings:
                return try await jsonResponse(handler.loadSettings())
            case .release:
                return try await jsonResponse(handler.loadReleaseInfo())
            case .installInfo:
                return try await jsonResponse(handler.loadInstallInfo())
            case .logText:
                let logRequest = try request.decodedBody(RuntimeLogTextRequest.self)
                return try await jsonResponse(handler.loadLogText(request: logRequest))
            case .logStream:
                let logRequest = try request.runtimeLogTextRequest()
                return try await eventStreamResponse(
                    id: "runtime-log-\(logRequest.source.rawValue)",
                    event: "runtime-log",
                    value: handler.loadLogText(request: logRequest)
                )
            case .applySettings,
                 .startServices,
                 .stopServices,
                 .repairProxy,
                 .repairDatastore,
                 .uninstall,
                 .backups,
                 .updateBundleSummary,
                 .verifyUpdateBundle,
                 .applyUpdateBundle,
                 .rollbackBackup,
                 .deleteBackup,
                 .exportLogs:
                return errorResponse(
                    status: .notImplemented,
                    code: .endpointNotImplemented,
                    message: "Endpoint is not implemented by this router."
                )
            }
        } catch let queryError as RuntimeControlHTTPQueryError {
            return errorResponse(
                status: .badRequest,
                code: .badRequest,
                message: queryError.localizedDescription
            )
        } catch {
            return errorResponse(
                status: .internalServerError,
                code: .handlerFailed,
                message: error.localizedDescription
            )
        }
    }

    private func streamResponse(
        _ endpoint: RuntimeControlAPIEndpoint,
        request: RuntimeControlHTTPRequest
    ) -> RuntimeControlHTTPStreamResponse? {
        switch endpoint {
        case .statusStream:
            return makeStream { [handler, streamConfiguration] continuation in
                await pollSnapshot(
                    id: "runtime-status",
                    event: "runtime-status",
                    interval: streamConfiguration.pollIntervalNanoseconds,
                    heartbeatInterval: streamConfiguration.heartbeatIntervalNanoseconds,
                    continuation: continuation
                ) {
                    try await handler.loadStatus()
                }
            }
        case .eventStream:
            do {
                let query = try request.runtimeEventQuery()
                let lastEventID = request.headerValue(named: "Last-Event-ID")
                return makeStream { [handler, streamConfiguration] continuation in
                    await pollEvents(
                        lastEventID: lastEventID,
                        interval: streamConfiguration.pollIntervalNanoseconds,
                        heartbeatInterval: streamConfiguration.heartbeatIntervalNanoseconds,
                        continuation: continuation
                    ) {
                        try await handler.loadEvents(query: query)
                    }
                }
            } catch let queryError as RuntimeControlHTTPQueryError {
                return errorStreamResponse(queryError.localizedDescription)
            } catch {
                return errorStreamResponse(error.localizedDescription)
            }
        case .vitalDBObservationStream:
            return makeStream { [handler, streamConfiguration] continuation in
                await pollSnapshot(
                    id: "vitaldb-observation",
                    event: "vitaldb-observed",
                    interval: streamConfiguration.pollIntervalNanoseconds,
                    heartbeatInterval: streamConfiguration.heartbeatIntervalNanoseconds,
                    continuation: continuation
                ) {
                    try await handler.loadVitalDBObservation()
                }
            }
        case .logStream:
            do {
                let logRequest = try request.runtimeLogTextRequest()
                return makeStream { [handler, streamConfiguration] continuation in
                    await pollSnapshot(
                        id: "runtime-log-\(logRequest.source.rawValue)",
                        event: "runtime-log",
                        interval: streamConfiguration.pollIntervalNanoseconds,
                        heartbeatInterval: streamConfiguration.heartbeatIntervalNanoseconds,
                        continuation: continuation
                    ) {
                        try await handler.loadLogText(request: logRequest)
                    }
                }
            } catch let queryError as RuntimeControlHTTPQueryError {
                return errorStreamResponse(queryError.localizedDescription)
            } catch {
                return errorStreamResponse(error.localizedDescription)
            }
        default:
            return nil
        }
    }

    private func jsonResponse<T: Encodable>(_ value: T) throws -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(value)
        )
    }

    private func eventStreamResponse(_ history: RuntimeEventHistory) throws -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .ok,
            headers: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            ],
            body: try RuntimeControlServerSentEventCodec.encode(history.events)
        )
    }

    private func eventStreamResponse<T: Encodable>(id: String, event: String, value: T) throws -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .ok,
            headers: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            ],
            body: try RuntimeControlServerSentEventCodec.encode(id: id, event: event, value: value)
        )
    }

    private func streamSnapshotResponse(_ stream: RuntimeControlHTTPStreamResponse) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: stream.status,
            headers: stream.headers,
            body: nil
        )
    }

    private func makeStream(
        _ operation: @escaping @MainActor @Sendable (AsyncThrowingStream<RuntimeControlServerSentEvent, Error>.Continuation) async -> Void
    ) -> RuntimeControlHTTPStreamResponse {
        let events = AsyncThrowingStream<RuntimeControlServerSentEvent, Error> { continuation in
            let task = Task { @MainActor in
                await operation(continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return RuntimeControlHTTPStreamResponse(
            status: .ok,
            headers: RuntimeControlServerSentEventCodec.streamHeaders,
            events: events
        )
    }

    private func errorStreamResponse(_ message: String) -> RuntimeControlHTTPStreamResponse {
        RuntimeControlHTTPStreamResponse(
            status: .badRequest,
            headers: RuntimeControlServerSentEventCodec.streamHeaders,
            events: AsyncThrowingStream { continuation in
                let error = RuntimeControlErrorResponse(code: .badRequest, message: message)
                let data = (try? JSONEncoder().encode(error)) ?? Data()
                continuation.yield(RuntimeControlServerSentEvent(id: nil, event: "runtime-control-error", data: data))
                continuation.finish()
            }
        )
    }

    private func errorResponse(
        status: RuntimeControlHTTPStatus,
        code: RuntimeControlAPIErrorCode,
        message: String
    ) -> RuntimeControlHTTPResponse {
        let response = RuntimeControlErrorResponse(code: code, message: message)
        return RuntimeControlHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json"],
            body: try? JSONEncoder().encode(response)
        )
    }
}

@MainActor
private func pollSnapshot<T: Encodable>(
    id: String,
    event: String,
    interval: UInt64,
    heartbeatInterval: UInt64,
    continuation: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>.Continuation,
    load: @escaping @MainActor @Sendable () async throws -> T
) async {
    var previousPayload: Data?
    var lastHeartbeat = Date()
    do {
        while !Task.isCancelled {
            let value = try await load()
            let payload = try JSONEncoder().encode(value)
            if payload != previousPayload {
                previousPayload = payload
                lastHeartbeat = Date()
                continuation.yield(RuntimeControlServerSentEvent(id: id, event: event, data: payload))
            } else if Date().timeIntervalSince(lastHeartbeat) >= Double(heartbeatInterval) / 1_000_000_000 {
                lastHeartbeat = Date()
                continuation.yield(.heartbeat)
            }
            try await Task.sleep(nanoseconds: interval)
        }
    } catch is CancellationError {
        continuation.finish()
    } catch {
        continuation.finish(throwing: error)
    }
}

@MainActor
private func pollEvents(
    lastEventID: String?,
    interval: UInt64,
    heartbeatInterval: UInt64,
    continuation: AsyncThrowingStream<RuntimeControlServerSentEvent, Error>.Continuation,
    load: @escaping @MainActor @Sendable () async throws -> RuntimeEventHistory
) async {
    var deliveredIDs = Set<String>()
    var hasAppliedReconnectCursor = lastEventID == nil
    var lastHeartbeat = Date()
    do {
        while !Task.isCancelled {
            let history = try await load()
            let currentIDs = Set(history.events.map(\.id))
            deliveredIDs.formIntersection(currentIDs)
            if !hasAppliedReconnectCursor, let lastEventID, !currentIDs.contains(lastEventID) {
                hasAppliedReconnectCursor = true
            }
            for event in history.events {
                if !hasAppliedReconnectCursor {
                    if event.id == lastEventID {
                        hasAppliedReconnectCursor = true
                    }
                    continue
                }
                guard !deliveredIDs.contains(event.id) else {
                    continue
                }
                deliveredIDs.insert(event.id)
                lastHeartbeat = Date()
                continuation.yield(try .event(event))
            }
            if Date().timeIntervalSince(lastHeartbeat) >= Double(heartbeatInterval) / 1_000_000_000 {
                lastHeartbeat = Date()
                continuation.yield(.heartbeat)
            }
            try await Task.sleep(nanoseconds: interval)
        }
    } catch is CancellationError {
        continuation.finish()
    } catch {
        continuation.finish(throwing: error)
    }
}

public enum RuntimeControlServerSentEventCodec {
    public static let streamHeaders = [
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
    ]

    public static func encode(_ events: [RuntimeEventDocument]) throws -> Data {
        let frames = try events.map { event in
            try encodeString(.event(event))
        }
        return Data(frames.joined(separator: "\n").utf8)
    }

    public static func encode<T: Encodable>(id: String, event: String, value: T) throws -> Data {
        let payload = try JSONEncoder().encode(value)
        return encode(RuntimeControlServerSentEvent(id: id, event: event, data: payload))
    }

    public static func encode(_ event: RuntimeControlServerSentEvent) -> Data {
        Data(encodeString(event).utf8)
    }

    private static func encodeString(_ event: RuntimeControlServerSentEvent) -> String {
        if let comment = event.comment {
            return ": \(comment)\n\n"
        }
        let data = event.data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        id: \(event.id ?? "")
        event: \(event.event ?? "message")
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

    public static func event(_ event: RuntimeEventDocument) throws -> RuntimeControlServerSentEvent {
        RuntimeControlServerSentEvent(
            id: event.id,
            event: event.eventType.rawValue,
            data: try JSONEncoder().encode(event)
        )
    }
}

public struct RuntimeControlAPIAuthorization: Equatable, Sendable {
    public let headerName: String
    public let token: String

    public init(headerName: String = "X-Runtime-Control-Token", token: String) {
        self.headerName = headerName
        self.token = token
    }

    public func allows(request: RuntimeControlHTTPRequest) -> Bool {
        request.headerValue(named: headerName) == token
    }
}

public extension RuntimeControlHTTPRequest {
    func headerValue(named name: String) -> String? {
        headers.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    func queryValue(named name: String) -> String? {
        queryParameters.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    var queryParameters: [String: String] {
        guard let components = URLComponents(string: path), let queryItems = components.queryItems else {
            return [:]
        }
        return queryItems.reduce(into: [:]) { result, item in
            guard let value = item.value else {
                return
            }
            result[item.name] = value
        }
    }

    func runtimeEventQuery() throws -> RuntimeEventQuery {
        let limit: Int
        if let rawLimit = queryValue(named: "limit") {
            guard let parsedLimit = Int(rawLimit), parsedLimit > 0 else {
                throw RuntimeControlHTTPQueryError.invalidLimit(rawLimit)
            }
            limit = parsedLimit
        } else {
            limit = RuntimeEventQuery.defaultLimit
        }

        let before: RuntimeEventCursor?
        if let rawCursor = queryValue(named: "cursor") {
            guard let decodedCursor = RuntimeEventCursorWireCodec.decode(rawCursor) else {
                throw RuntimeControlHTTPQueryError.invalidCursor(rawCursor)
            }
            before = decodedCursor
        } else {
            before = nil
        }

        return RuntimeEventQuery(
            limit: limit,
            eventType: queryValue(named: "type").map(RuntimeEventType.init(rawValue:)),
            since: queryValue(named: "since"),
            before: before
        )
    }

    func runtimeLogTextRequest() throws -> RuntimeLogTextRequest {
        let source: RuntimeLogSource
        if let rawSource = queryValue(named: "source") {
            guard let parsedSource = RuntimeLogSource(rawValue: rawSource) else {
                throw RuntimeControlHTTPQueryError.invalidLogSource(rawSource)
            }
            source = parsedSource
        } else {
            source = .helperMessage
        }

        let lineLimit: Int
        if let rawLimit = queryValue(named: "lineLimit") {
            guard let parsedLimit = Int(rawLimit), parsedLimit > 0 else {
                throw RuntimeControlHTTPQueryError.invalidLimit(rawLimit)
            }
            lineLimit = parsedLimit
        } else {
            lineLimit = 200
        }

        return RuntimeLogTextRequest(
            source: source,
            helperMessage: queryValue(named: "helperMessage") ?? "",
            lineLimit: lineLimit
        )
    }

    func decodedBody<T: Decodable>(_ type: T.Type) throws -> T {
        guard let body else {
            throw RuntimeControlHTTPQueryError.missingBody
        }
        do {
            return try JSONDecoder().decode(type, from: body)
        } catch {
            throw RuntimeControlHTTPQueryError.invalidBody
        }
    }
}

public enum RuntimeControlHTTPQueryError: LocalizedError, Equatable {
    case invalidLimit(String)
    case invalidCursor(String)
    case invalidLogSource(String)
    case missingBody
    case invalidBody

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let value):
            return "Invalid runtime event limit: \(value)"
        case .invalidCursor(let value):
            return "Invalid runtime event cursor: \(value)"
        case .invalidLogSource(let value):
            return "Invalid runtime log source: \(value)"
        case .missingBody:
            return "Missing request body."
        case .invalidBody:
            return "Invalid request body."
        }
    }
}
