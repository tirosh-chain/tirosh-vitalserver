import Foundation
import RuntimeControl

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

@MainActor
public protocol RuntimeControlAPIReadHandler {
    func loadCapabilities() async throws -> RuntimeControlCapabilities
    func loadStatus() async throws -> RuntimeStatus
    func loadEvents(query: RuntimeControlEventQuery) async throws -> RuntimeEventHistory
    func loadHealthStatus() async throws -> RuntimeStatus
    func loadSettings() async throws -> RuntimeSettings
    func loadReleaseInfo() async throws -> RuntimeReleaseInfo
    func loadInstallInfo() async throws -> RuntimeInstallInfo
}

@MainActor
public struct RuntimeControlAPIRouter {
    private let handler: any RuntimeControlAPIReadHandler
    private let authorization: RuntimeControlAPIAuthorization?

    public init(
        handler: any RuntimeControlAPIReadHandler,
        authorization: RuntimeControlAPIAuthorization? = nil
    ) {
        self.handler = handler
        self.authorization = authorization
    }

    public func route(_ request: RuntimeControlHTTPRequest) async -> RuntimeControlHTTPResponse {
        if let authorization, !authorization.allows(request: request) {
            return errorResponse(
                status: .unauthorized,
                code: .unauthorized,
                message: "Runtime Control token is missing or invalid."
            )
        }

        if let endpoint = RuntimeControlAPIEndpoint.matching(method: request.method, path: request.path) {
            return await route(endpoint, request: request)
        }

        guard RuntimeControlAPIEndpoint.matching(path: request.path) != nil else {
            return errorResponse(status: .notFound, code: .routeNotFound, message: "Route not found.")
        }

        return errorResponse(
            status: .methodNotAllowed,
            code: .methodNotAllowed,
            message: "Method is not allowed for this route."
        )
    }

    private func route(_ endpoint: RuntimeControlAPIEndpoint, request: RuntimeControlHTTPRequest) async -> RuntimeControlHTTPResponse {
        do {
            switch endpoint {
            case .capabilities:
                return try await jsonResponse(handler.loadCapabilities())
            case .status:
                return try await jsonResponse(handler.loadStatus())
            case .events:
                return try await jsonResponse(handler.loadEvents(query: try request.runtimeEventQuery()))
            case .health:
                return try await jsonResponse(handler.loadHealthStatus())
            case .settings:
                return try await jsonResponse(handler.loadSettings())
            case .release:
                return try await jsonResponse(handler.loadReleaseInfo())
            case .installInfo:
                return try await jsonResponse(handler.loadInstallInfo())
            case .applySettings,
                 .startServices,
                 .stopServices,
                 .repairProxy,
                 .repairDatastore,
                 .uninstall,
                 .backups,
                 .logText,
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

    private func jsonResponse<T: Encodable>(_ value: T) throws -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(value)
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

    func runtimeEventQuery() throws -> RuntimeControlEventQuery {
        let limit: Int
        if let rawLimit = queryValue(named: "limit") {
            guard let parsedLimit = Int(rawLimit), parsedLimit > 0 else {
                throw RuntimeControlHTTPQueryError.invalidLimit(rawLimit)
            }
            limit = parsedLimit
        } else {
            limit = RuntimeControlEventQuery.defaultLimit
        }

        return RuntimeControlEventQuery(
            limit: limit,
            eventType: queryValue(named: "type"),
            since: queryValue(named: "since")
        )
    }
}

public enum RuntimeControlHTTPQueryError: LocalizedError, Equatable {
    case invalidLimit(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let value):
            return "Invalid runtime event limit: \(value)"
        }
    }
}
