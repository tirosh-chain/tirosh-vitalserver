import Foundation

public enum RuntimeControlHTTPMethod: String, CaseIterable, Codable, Equatable, Sendable {
    case get = "GET"
    case options = "OPTIONS"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public enum RuntimeControlAPIScope: String, Codable, Equatable, Sendable {
    case runtimeControl
    case platformAffordance
}

public enum RuntimeControlAPIClientAccess: String, Codable, Equatable, Sendable {
    case browserSafe
    case localServerMediated
    case nativeShellOnly
}

public enum RuntimeControlAPIStreamCapability: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
}

public enum RuntimeControlAPIErrorCode: String, CaseIterable, Codable, Equatable, Sendable {
    case badRequest
    case routeNotFound
    case resourceNotFound
    case methodNotAllowed
    case unauthorized
    case endpointNotImplemented
    case platformAffordanceUnavailable
    case updateApplyUnavailable
    case operationInProgress
    case guestControlUnavailable
    case handlerFailed
}

public struct RuntimeControlAPIRoute: Codable, Equatable, Sendable {
    public let method: RuntimeControlHTTPMethod
    public let path: String
    public let scope: RuntimeControlAPIScope

    public init(method: RuntimeControlHTTPMethod, path: String, scope: RuntimeControlAPIScope) {
        self.method = method
        self.path = path
        self.scope = scope
    }
}
