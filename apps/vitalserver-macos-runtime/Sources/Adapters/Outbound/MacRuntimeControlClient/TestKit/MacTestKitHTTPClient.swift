import Foundation

public protocol MacTestKitHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse)
}

public struct URLSessionMacTestKitHTTPClient: MacTestKitHTTPClient {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }

    public func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.upload(for: request, fromFile: fileURL)
    }
}
