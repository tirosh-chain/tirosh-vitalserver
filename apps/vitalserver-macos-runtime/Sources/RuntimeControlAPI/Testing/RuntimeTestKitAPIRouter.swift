import Foundation
import RuntimeControl

@MainActor
public struct RuntimeTestKitAPIRouter {
    private let controller: any RuntimeTestKitControlling
    private let authorization: RuntimeControlAPIAuthorization?

    public init(
        controller: any RuntimeTestKitControlling,
        authorization: RuntimeControlAPIAuthorization? = nil
    ) {
        self.controller = controller
        self.authorization = authorization
    }

    public func routeResult(_ request: RuntimeControlHTTPRequest) async -> RuntimeControlHTTPRouteResult? {
        guard let endpoint = RuntimeTestKitAPIEndpoint.matching(method: request.method, path: request.path) else {
            return nil
        }

        if let authorization, !authorization.allows(request: request) {
            return .response(errorResponse(
                status: .unauthorized,
                code: .unauthorized,
                message: "Runtime Control token is missing or invalid."
            ))
        }

        return .response(await route(endpoint, request: request))
    }

    private func route(
        _ endpoint: RuntimeTestKitAPIEndpoint,
        request: RuntimeControlHTTPRequest
    ) async -> RuntimeControlHTTPResponse {
        do {
            switch endpoint {
            case .status:
                return try await jsonResponse(controller.loadTestKitStatus())
            case .startVirtualRecorders:
                let startRequest = try request.decodedBody(RuntimeTestKitVirtualRecorderStartRequest.self)
                return try await jsonResponse(controller.startVirtualRecorders(startRequest))
            case .stopVirtualRecorders:
                let stopRequest = try request.optionalDecodedBody(RuntimeTestKitStopRequest.self)
                return try await jsonResponse(controller.stopVirtualRecorders(sessionID: stopRequest?.sessionID))
            case .deleteVirtualRecorders:
                let deleteRequest = try request.optionalDecodedBody(RuntimeTestKitDeleteRequest.self)
                return try await jsonResponse(controller.deleteVirtualRecorders(sessionID: deleteRequest?.sessionID))
            case .resetVirtualRecorders:
                return try await jsonResponse(controller.resetVirtualRecorders())
            }
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

public enum RuntimeTestKitAPIEndpoint: String, CaseIterable, Codable, Equatable, Sendable {
    case status
    case startVirtualRecorders
    case stopVirtualRecorders
    case deleteVirtualRecorders
    case resetVirtualRecorders

    public var method: RuntimeControlHTTPMethod {
        switch self {
        case .status:
            return .get
        case .startVirtualRecorders, .stopVirtualRecorders,
             .deleteVirtualRecorders, .resetVirtualRecorders:
            return .post
        }
    }

    public var path: String {
        switch self {
        case .status:
            return "/dev/testkit/status"
        case .startVirtualRecorders:
            return "/dev/testkit/virtual-recorders/start"
        case .stopVirtualRecorders:
            return "/dev/testkit/virtual-recorders/stop"
        case .deleteVirtualRecorders:
            return "/dev/testkit/virtual-recorders/delete"
        case .resetVirtualRecorders:
            return "/dev/testkit/virtual-recorders/reset"
        }
    }

    public static func matching(method: RuntimeControlHTTPMethod, path: String) -> RuntimeTestKitAPIEndpoint? {
        let normalizedPath = normalizedPath(path)
        return allCases.first { endpoint in
            endpoint.method == method && endpoint.path == normalizedPath
        }
    }

    public static func matches(path: String) -> Bool {
        let normalizedPath = normalizedPath(path)
        return allCases.contains { endpoint in
            endpoint.path == normalizedPath
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard let queryIndex = path.firstIndex(of: "?") else {
            return path
        }
        return String(path[..<queryIndex])
    }
}

public struct RuntimeTestKitStopRequest: Codable, Equatable, Sendable {
    public let sessionID: String?

    public init(sessionID: String? = nil) {
        self.sessionID = sessionID
    }
}

public struct RuntimeTestKitDeleteRequest: Codable, Equatable, Sendable {
    public let sessionID: String?

    public init(sessionID: String? = nil) {
        self.sessionID = sessionID
    }
}

private extension RuntimeControlHTTPRequest {
    func optionalDecodedBody<T: Decodable>(_ type: T.Type) throws -> T? {
        guard let body, !body.isEmpty else {
            return nil
        }
        return try JSONDecoder().decode(type, from: body)
    }
}
