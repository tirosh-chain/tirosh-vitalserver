import Foundation
import Errors

struct MacTestKitAPIClient: Sendable {
    private let httpClient: any MacTestKitHTTPClient
    private let healthRead: (@Sendable (String) async -> MacTestKitAPIHealthRead)?
    private let requestTimeout: TimeInterval

    init(
        httpClient: any MacTestKitHTTPClient,
        healthRead: (@Sendable (String) async -> MacTestKitAPIHealthRead)?,
        requestTimeout: TimeInterval = 5
    ) {
        self.httpClient = httpClient
        self.healthRead = healthRead
        self.requestTimeout = requestTimeout
    }

    func health(apiBaseURL: String) async -> MacTestKitAPIHealthRead {
        if let healthRead {
            return await healthRead(apiBaseURL)
        }
        return await defaultHealthCheck(apiBaseURL: apiBaseURL)
    }

    func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacTestKitControllerError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            guard let message = String(data: data, encoding: .utf8) else {
                throw MacTestKitControllerError.requestFailed(
                    "HTTP \(httpResponse.statusCode) response body is not valid UTF-8"
                )
            }
            throw MacTestKitControllerError.requestFailed(message)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    func request(
        apiBaseURL: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        URLRequest(
            url: try url(apiBaseURL: apiBaseURL, path: path, queryItems: queryItems),
            timeoutInterval: requestTimeout
        )
    }

    private func url(
        apiBaseURL: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(string: "\(apiBaseURL)\(path)") else {
            throw MacTestKitControllerError.invalidRequestURL(
                "TestKit API request URL is invalid baseURL=\(apiBaseURL) path=\(path)"
            )
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw MacTestKitControllerError.invalidRequestURL(
                "TestKit API request URL could not be constructed baseURL=\(apiBaseURL) path=\(path)"
            )
        }
        return url
    }

    private func defaultHealthCheck(apiBaseURL: String) async -> MacTestKitAPIHealthRead {
        do {
            var request = URLRequest(
                url: try url(apiBaseURL: apiBaseURL, path: "/health"),
                timeoutInterval: requestTimeout
            )
            request.httpMethod = "GET"
            let (_, response) = try await httpClient.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unreachable("health endpoint returned a non-HTTP response")
            }
            guard httpResponse.statusCode == 200 else {
                return .unreachable("health endpoint returned HTTP \(httpResponse.statusCode)")
            }
            return .healthy
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}

enum MacTestKitAPIHealthRead: Equatable, Sendable {
    case healthy
    case unreachable(String?)

    var isHealthy: Bool {
        self == .healthy
    }

    var issue: String? {
        switch self {
        case .healthy:
            nil
        case .unreachable(let message):
            message
        }
    }
}
