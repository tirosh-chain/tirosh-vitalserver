import Contracts
import RuntimeControl

@MainActor
struct RuntimeControlHTTPRouteExecutor {
    let handler: any RuntimeControlAPIReadHandler

    func route(
        _ endpoint: RuntimeControlAPIEndpoint,
        request: RuntimeControlHTTPRequest
    ) async -> RuntimeControlHTTPResponse {
        do {
            if let response = try await RuntimeControlHTTPReadRoutes(handler: handler)
                .route(endpoint, request: request) {
                return response
            }
            if let response = try await RuntimeControlHTTPCommandRoutes(handler: handler)
                .route(endpoint, request: request) {
                return response
            }
            return RuntimeControlHTTPResponseFactory.error(
                status: .notImplemented,
                code: .endpointNotImplemented,
                message: "Endpoint is not implemented by this router."
            )
        } catch {
            return RuntimeControlHTTPErrorResponseMapper.response(for: error)
        }
    }
}
