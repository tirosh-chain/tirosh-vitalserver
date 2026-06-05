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
            case .createBeds:
                let createRequest = try request.decodedBody(RuntimeTestKitCreateBedsRequest.self)
                return try await jsonResponse(controller.createTestKitBeds(createRequest))
            case .deleteBeds:
                let deleteRequest = try request.decodedBody(RuntimeTestKitDeleteBedsRequest.self)
                return try await jsonResponse(controller.deleteTestKitBeds(deleteRequest))
            case .resetBeds:
                return try await jsonResponse(controller.resetTestKitBeds())
            case .startVirtualRecorders:
                let startRequest = try request.decodedBody(RuntimeTestKitVirtualRecorderStartRequest.self)
                return try await jsonResponse(controller.startVirtualRecorders(startRequest))
            case .pauseVirtualRecorders:
                let pauseRequest = try request.decodedBody(RuntimeTestKitStopRequest.self)
                return try await jsonResponse(controller.pauseVirtualRecorders(
                    sessionID: requiredSessionID(pauseRequest.sessionID)
                ))
            case .resumeVirtualRecorders:
                let resumeRequest = try request.decodedBody(RuntimeTestKitStopRequest.self)
                return try await jsonResponse(controller.resumeVirtualRecorders(
                    sessionID: requiredSessionID(resumeRequest.sessionID)
                ))
            case .stopVirtualRecorders:
                let stopRequest = try request.decodedBody(RuntimeTestKitStopRequest.self)
                return try await jsonResponse(controller.stopVirtualRecorders(
                    sessionID: requiredSessionID(stopRequest.sessionID)
                ))
            case .restartVirtualRecorders:
                let restartRequest = try request.decodedBody(RuntimeTestKitRestartRequest.self)
                return try await jsonResponse(controller.restartVirtualRecorders(
                    sessionID: restartRequest.sessionID,
                    bedRoomNames: restartRequest.bedRoomNames
                ))
            case .deleteVirtualRecorders:
                let deleteRequest = try request.decodedBody(RuntimeTestKitDeleteRequest.self)
                return try await jsonResponse(controller.deleteVirtualRecorders(
                    sessionID: requiredSessionID(deleteRequest.sessionID)
                ))
            case .deleteVirtualRecorder:
                let deleteRequest = try request.decodedBody(RuntimeTestKitRecorderDeletionRequest.self)
                return try await jsonResponse(controller.deleteVirtualRecorder(vrcode: deleteRequest.vrcode))
            case .resetVirtualRecorders:
                return try await jsonResponse(controller.resetVirtualRecorders())
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

    private func requiredSessionID(_ value: String) throws -> String {
        let sessionID = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty else {
            throw RuntimeControlHTTPQueryError.invalidBody("sessionID is required.")
        }
        return sessionID
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
        return RuntimeControlHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json"],
            body: RuntimeControlErrorResponseEncoder.encode(code: code, message: message)
        )
    }
}

public enum RuntimeTestKitAPIEndpoint: String, CaseIterable, Codable, Equatable, Sendable {
    case status
    case createBeds
    case deleteBeds
    case resetBeds
    case startVirtualRecorders
    case pauseVirtualRecorders
    case resumeVirtualRecorders
    case stopVirtualRecorders
    case restartVirtualRecorders
    case deleteVirtualRecorders
    case deleteVirtualRecorder
    case resetVirtualRecorders

    public var method: RuntimeControlHTTPMethod {
        switch self {
        case .status:
            return .get
        case .createBeds, .deleteBeds, .resetBeds,
             .startVirtualRecorders, .pauseVirtualRecorders,
             .resumeVirtualRecorders, .stopVirtualRecorders,
             .restartVirtualRecorders,
             .deleteVirtualRecorders, .deleteVirtualRecorder,
             .resetVirtualRecorders:
            return .post
        }
    }

    public var path: String {
        switch self {
        case .status:
            return "/dev/testkit/status"
        case .createBeds:
            return "/dev/testkit/beds/create"
        case .deleteBeds:
            return "/dev/testkit/beds/delete"
        case .resetBeds:
            return "/dev/testkit/beds/reset"
        case .startVirtualRecorders:
            return "/dev/testkit/virtual-recorders/start"
        case .pauseVirtualRecorders:
            return "/dev/testkit/virtual-recorders/pause"
        case .resumeVirtualRecorders:
            return "/dev/testkit/virtual-recorders/resume"
        case .stopVirtualRecorders:
            return "/dev/testkit/virtual-recorders/stop"
        case .restartVirtualRecorders:
            return "/dev/testkit/virtual-recorders/restart"
        case .deleteVirtualRecorders:
            return "/dev/testkit/virtual-recorders/delete"
        case .deleteVirtualRecorder:
            return "/dev/testkit/virtual-recorders/delete-orphan"
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
    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

public struct RuntimeTestKitDeleteRequest: Codable, Equatable, Sendable {
    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}

public struct RuntimeTestKitRestartRequest: Codable, Equatable, Sendable {
    public let sessionID: String
    public let bedRoomNames: [String]

    public init(sessionID: String, bedRoomNames: [String]) {
        self.sessionID = sessionID
        self.bedRoomNames = bedRoomNames
    }
}

public struct RuntimeTestKitRecorderDeletionRequest: Codable, Equatable, Sendable {
    public let vrcode: String

    public init(vrcode: String) {
        self.vrcode = vrcode
    }
}
