import CryptoKit
import Foundation

public struct RuntimeControlLoopbackBrowserSession: Equatable, Sendable {
    public static let bootstrapPath = "/platform/browser-session"
    public static let cookieName = "vitalserver_platform_session"
    private static let lifetimeSeconds = 8 * 60 * 60

    public let token: String

    public init(token: String? = nil) {
        self.token = token ?? Self.generatedToken()
    }

    public func allows(request: RuntimeControlHTTPRequest) -> Bool {
        guard let cookieHeader = request.headerValue(named: "Cookie") else {
            return false
        }
        return cookieHeader.split(separator: ";").contains { segment in
            let parts = segment.trimmingCharacters(in: .whitespaces)
                .split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2
                && parts[0] == Substring(Self.cookieName)
                && parts[1] == Substring(token)
        }
    }

    public func isSameOrigin(request: RuntimeControlHTTPRequest, port: UInt16?) -> Bool {
        guard let port else {
            return false
        }
        return request.headerValue(named: "Origin") == "http://127.0.0.1:\(port)"
    }

    public func needsOriginCheck(request: RuntimeControlHTTPRequest) -> Bool {
        switch request.method {
        case .post, .put, .delete:
            return true
        case .get, .options:
            return false
        }
    }

    public func bootstrapResponse(
        for request: RuntimeControlHTTPRequest,
        port: UInt16?
    ) -> RuntimeControlHTTPResponse {
        guard request.method == .post,
              request.path == Self.bootstrapPath,
              isSameOrigin(request: request, port: port) else {
            return RuntimeControlHTTPResponseFactory.error(
                status: .unauthorized,
                code: .unauthorized,
                message: "Local browser session origin is missing or invalid."
            )
        }
        return RuntimeControlHTTPResponse(
            status: .noContent,
            headers: ["Set-Cookie": cookieHeader]
        )
    }

    private var cookieHeader: String {
        "\(Self.cookieName)=\(token); Path=/; HttpOnly; SameSite=Strict; Max-Age=\(Self.lifetimeSeconds)"
    }

    private static func generatedToken() -> String {
        let key = SymmetricKey(size: .bits256)
        let encoded = key.withUnsafeBytes { Data($0).base64EncodedString() }
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct RuntimeControlAPIAuthorization: Equatable, Sendable {
    public let headerName: String
    public let token: String
    public let browserSession: RuntimeControlLoopbackBrowserSession?

    public init(
        headerName: String = "X-Runtime-Control-Token",
        token: String,
        browserSession: RuntimeControlLoopbackBrowserSession? = nil
    ) {
        self.headerName = headerName
        self.token = token
        self.browserSession = browserSession
    }

    public func allows(request: RuntimeControlHTTPRequest) -> Bool {
        request.headerValue(named: headerName) == token || browserSession?.allows(request: request) == true
    }
}
