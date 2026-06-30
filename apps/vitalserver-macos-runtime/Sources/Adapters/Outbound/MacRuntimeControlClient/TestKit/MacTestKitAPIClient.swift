import Foundation
import Errors

struct MacTestKitAPIClient: Sendable {
    private let httpClient: any MacTestKitHTTPClient
    private let healthRead: (@Sendable (String) async -> MacTestKitAPIHealthRead)?
    private let standardRequestTimeout: TimeInterval
    private let longRunningRequestTimeout: TimeInterval

    init(
        httpClient: any MacTestKitHTTPClient,
        healthRead: (@Sendable (String) async -> MacTestKitAPIHealthRead)?,
        standardRequestTimeout: TimeInterval = 5,
        longRunningRequestTimeout: TimeInterval = 60
    ) {
        self.httpClient = httpClient
        self.healthRead = healthRead
        self.standardRequestTimeout = standardRequestTimeout
        self.longRunningRequestTimeout = longRunningRequestTimeout
    }

    func health(apiBaseURL: String) async -> MacTestKitAPIHealthRead {
        if let healthRead {
            return await healthRead(apiBaseURL)
        }
        return await defaultHealthCheck(apiBaseURL: apiBaseURL)
    }

    func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await httpClient.data(for: request)
        return try decoded(type, data: data, response: response)
    }

    func send(_ request: URLRequest, bodyFileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await httpClient.upload(for: request, fromFile: bodyFileURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacTestKitControllerError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func decoded<T: Decodable>(
        _ type: T.Type,
        data: Data,
        response: URLResponse
    ) throws -> T {
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
        queryItems: [URLQueryItem] = [],
        timeout: MacTestKitAPIRequestTimeout = .standard
    ) throws -> URLRequest {
        URLRequest(
            url: try url(apiBaseURL: apiBaseURL, path: path, queryItems: queryItems),
            timeoutInterval: timeoutInterval(for: timeout)
        )
    }

    private func timeoutInterval(for timeout: MacTestKitAPIRequestTimeout) -> TimeInterval {
        switch timeout {
        case .standard:
            standardRequestTimeout
        case .longRunningCommand:
            longRunningRequestTimeout
        }
    }

    private func url(
        apiBaseURL: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(string: joinedURL(apiBaseURL: apiBaseURL, path: path)) else {
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

    private func joinedURL(apiBaseURL: String, path: String) -> String {
        apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/"
            + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func defaultHealthCheck(apiBaseURL: String) async -> MacTestKitAPIHealthRead {
        do {
            var request = URLRequest(
                url: try url(apiBaseURL: apiBaseURL, path: "/health"),
                timeoutInterval: standardRequestTimeout
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

enum MacTestKitAPIRequestTimeout: Sendable {
    case standard
    case longRunningCommand
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
