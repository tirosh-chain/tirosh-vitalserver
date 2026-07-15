import Contracts
import Foundation
import RuntimeControl

/// Reads Host-owned platform state through the root Platform Agent contract.
/// The `settings` argument exists only because of the legacy client interface and
/// must never be used to reconstruct platform state in this adapter.
public struct RuntimeControlAPIPlatformStateReader: PlatformStateReading {
    private let baseURL: URL
    private let httpClient: any RuntimeControlClientHTTPClient
    private let decoder: JSONDecoder

    public init(
        baseURL: String,
        httpClient: any RuntimeControlClientHTTPClient,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        guard let url = URL(string: baseURL) else {
            throw RuntimeControlClientHTTPClientError.invalidBaseURL(baseURL)
        }
        self.baseURL = url
        self.httpClient = httpClient
        self.decoder = decoder
    }

    public func loadPlatformState(settings _: RuntimeSettings) -> PlatformState {
        load(method: "GET", path: "platform", source: "platformState")
    }

    public func loadHealthStatus(settings _: RuntimeSettings) async -> PlatformState {
        load(method: "POST", path: "platform/health", source: "platformHealth")
    }

    private func load(method: String, path: String, source: String) -> PlatformState {
        do {
            return try loadContract(method: method, path: path)
        } catch {
            let reason = String(describing: error)
            return PlatformStateReadFailureAssembler.make(source: source, reason: reason)
        }
    }

    private func loadContract(method: String, path: String) throws -> PlatformState {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw RuntimeControlClientHTTPClientError.invalidRequestURL(
                baseURL: baseURL.absoluteString,
                path: "/\(path)"
            )
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw RuntimeControlClientHTTPClientError.requestFailed(
                statusCode: response.statusCode,
                detail: String(data: response.data, encoding: .utf8) ?? "invalid UTF-8 response"
            )
        }
        do {
            return try decoder.decode(PlatformState.self, from: response.data)
        } catch {
            throw RuntimeControlClientHTTPClientError.decodeFailed(error.localizedDescription)
        }
    }
}
