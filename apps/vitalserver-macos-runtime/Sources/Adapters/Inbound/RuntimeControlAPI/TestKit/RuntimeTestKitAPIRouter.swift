import Foundation
import RuntimeControl
import Errors

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
            return .response(RuntimeControlHTTPResponseFactory.error(
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
        } catch {
            return RuntimeControlHTTPErrorResponseMapper.response(for: error)
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

}
