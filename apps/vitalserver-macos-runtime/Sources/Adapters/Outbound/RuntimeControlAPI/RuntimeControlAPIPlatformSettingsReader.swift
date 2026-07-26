import Contracts
import Foundation
import RuntimeControl

public struct RuntimeControlAPIPlatformSettingsReader: RuntimeSettingsReading {
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

    public func load() -> RuntimeSettings {
        do {
            let read = try loadReadContract()
            guard read.state == .loaded, let settings = read.settings else {
                return failedSettings(
                    read.readError ?? "Platform settings API reported state=\(read.state.rawValue)"
                )
            }
            return settings.runtimeSettings
        } catch {
            return failedSettings(String(describing: error))
        }
    }

    private func loadReadContract() throws -> RuntimePlatformSettingsRead {
        guard let url = URL(string: "platform/settings", relativeTo: baseURL) else {
            throw RuntimeControlClientHTTPClientError.invalidRequestURL(
                baseURL: baseURL.absoluteString,
                path: "/platform/settings"
            )
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try httpClient.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw RuntimeControlClientHTTPClientError.requestFailed(
                statusCode: response.statusCode,
                detail: String(data: response.data, encoding: .utf8) ?? "invalid UTF-8 response"
            )
        }
        do {
            return try decoder.decode(RuntimePlatformSettingsRead.self, from: response.data)
        } catch {
            throw RuntimeControlClientHTTPClientError.decodeFailed(error.localizedDescription)
        }
    }

    private func failedSettings(_ reason: String) -> RuntimeSettings {
        RuntimeSettings(readIssues: [
            RuntimeSettingsReadIssue(source: "platformSettings", message: reason)
        ])
    }
}
