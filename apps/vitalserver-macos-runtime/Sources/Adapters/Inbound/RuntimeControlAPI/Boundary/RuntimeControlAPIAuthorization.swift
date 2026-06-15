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
