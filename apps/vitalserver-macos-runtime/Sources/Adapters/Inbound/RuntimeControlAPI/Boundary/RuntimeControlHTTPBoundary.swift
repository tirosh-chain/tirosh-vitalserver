import Foundation
import RuntimeControl

@MainActor
public struct RuntimeControlAPIRouter {
    private let handler: any RuntimeControlAPIReadHandler
    private let authorization: RuntimeControlAPIAuthorization?
    private let streamConfiguration: RuntimeControlAPIStreamConfiguration
    private let now: @Sendable () -> Date

    public init(
        handler: any RuntimeControlAPIReadHandler,
        authorization: RuntimeControlAPIAuthorization? = nil,
        streamConfiguration: RuntimeControlAPIStreamConfiguration = RuntimeControlAPIStreamConfiguration(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.handler = handler
        self.authorization = authorization
        self.streamConfiguration = streamConfiguration
        self.now = now
    }

    public func routeResult(_ request: RuntimeControlHTTPRequest) async -> RuntimeControlHTTPRouteResult {
        if let authorization, !authorization.allows(request: request) {
            return .response(RuntimeControlHTTPResponseFactory.error(
                status: .unauthorized,
                code: .unauthorized,
                message: "Runtime Control token is missing or invalid."
            ))
        }

        if let endpoint = RuntimeControlAPIEndpoint.matching(method: request.method, path: request.path) {
            if endpoint.streamCapability == .supported {
                return .stream(RuntimeControlHTTPStreamRoutes(
                    handler: handler,
                    configuration: streamConfiguration,
                    now: now
                ).streamResponse(endpoint, request: request))
            }
            return .response(await RuntimeControlHTTPRouteExecutor(handler: handler)
                .route(endpoint, request: request))
        }

        guard RuntimeControlAPIEndpoint.matching(path: request.path) != nil else {
            return .response(RuntimeControlHTTPResponseFactory.error(
                status: .notFound,
                code: .routeNotFound,
                message: "Route not found."
            ))
        }

        return .response(RuntimeControlHTTPResponseFactory.error(
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
            return RuntimeControlHTTPResponseFactory.streamSnapshot(stream)
        }
    }
}
