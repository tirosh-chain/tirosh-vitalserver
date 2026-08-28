import Foundation
import RuntimeControl

/// Reads the complete Host-owned operation state from the privileged Platform Agent.
/// A transport or decode failure remains an explicit unavailable resource.
public struct RuntimeControlAPIOperationStateReader: PlatformOperationStateReading {
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

    public func loadOperationState() -> PlatformOperationState {
        do {
            guard let url = URL(string: "platform/operations", relativeTo: baseURL) else {
                throw RuntimeControlClientHTTPClientError.invalidRequestURL(
                    baseURL: baseURL.absoluteString,
                    path: "/platform/operations"
                )
            }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response = try httpClient.send(request)
            guard (200...299).contains(response.statusCode) else {
                throw RuntimeControlClientHTTPClientError.requestFailed(
                    statusCode: response.statusCode,
                    detail: String(data: response.data, encoding: .utf8)
                        ?? "invalid UTF-8 response"
                )
            }
            return try decoder.decode(PlatformOperationState.self, from: response.data)
        } catch {
            let reason = "Platform Agent operation state read failed: \(error)"
            return PlatformOperationState(
                activeOperation: nil,
                install: .unavailable(readError: reason),
                lease: .unavailable(readError: reason),
                workflow: .unavailable(readError: reason),
                stableUpdate: .unavailable(readError: reason)
            )
        }
    }
}
