import Foundation
import Contracts

public final class RuntimeControlAPILocalSessionHTTPClient:
    RuntimeControlClientHTTPClient,
    @unchecked Sendable
{
    private let session: URLSession
    private let lock = NSLock()
    private var sessionCookiesByOrigin: [String: String] = [:]

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = HTTPCookieStorage()
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) throws -> RuntimeControlClientHTTPResponse {
        guard let url = request.url,
              let scheme = url.scheme,
              let host = url.host,
              let port = url.port else {
            throw RuntimeControlClientHTTPClientError.invalidHTTPResponse(
                "local Runtime Control session request has no explicit loopback origin"
            )
        }
        let origin = "\(scheme)://\(host):\(port)"
        guard host == "127.0.0.1" else {
            throw RuntimeControlClientHTTPClientError.invalidHTTPResponse(
                "local Runtime Control session requires a 127.0.0.1 endpoint host=\(host)"
            )
        }

        lock.lock()
        defer { lock.unlock() }
        if sessionCookiesByOrigin[origin] == nil {
            sessionCookiesByOrigin[origin] = try bootstrap(origin: origin)
        }
        var authorized = request
        authorized.setValue(origin, forHTTPHeaderField: "Origin")
        authorized.setValue(sessionCookiesByOrigin[origin], forHTTPHeaderField: "Cookie")
        return try perform(authorized)
    }

    private func bootstrap(origin: String) throws -> String {
        guard let url = URL(string: "\(origin)/platform/browser-session") else {
            throw RuntimeControlClientHTTPClientError.invalidBaseURL(origin)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try perform(request)
        guard response.statusCode == 204 else {
            throw RuntimeControlClientHTTPClientError.requestFailed(
                statusCode: response.statusCode,
                detail: String(data: response.data, encoding: .utf8) ?? "invalid UTF-8 response"
            )
        }
        guard let setCookie = response.headerValue(named: "Set-Cookie"),
              let cookie = setCookie.split(separator: ";", maxSplits: 1).first,
              cookie.hasPrefix("\(RuntimeControlLoopbackSessionContract.cookieName)=") else {
            throw RuntimeControlClientHTTPClientError.invalidHTTPResponse(
                "local Runtime Control session bootstrap did not return its session cookie"
            )
        }
        return String(cookie)
    }

    private func perform(_ request: URLRequest) throws -> RuntimeControlClientHTTPResponse {
        let resultBox = RuntimeControlLocalSessionHTTPResultBox()
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                resultBox.store(.failure(RuntimeControlClientHTTPClientError.transportFailed(
                    url: request.url?.absoluteString ?? "unknown",
                    reason: error.localizedDescription
                )))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                resultBox.store(.failure(RuntimeControlClientHTTPClientError.invalidHTTPResponse(
                    "local Runtime Control session returned a non-HTTP response"
                )))
                return
            }
            resultBox.store(.success(RuntimeControlClientHTTPResponse(
                statusCode: response.statusCode,
                data: data ?? Data(),
                headers: response.allHeaderFields.reduce(into: [:]) { headers, entry in
                    guard let name = entry.key as? String else { return }
                    headers[name] = String(describing: entry.value)
                }
            )))
        }
        task.resume()
        return try resultBox.wait()
    }
}

private final class RuntimeControlLocalSessionHTTPResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<RuntimeControlClientHTTPResponse, Error>?

    func store(_ result: Result<RuntimeControlClientHTTPResponse, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait() throws -> RuntimeControlClientHTTPResponse {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw RuntimeControlClientHTTPClientError.invalidHTTPResponse(
                "local Runtime Control session did not produce a response"
            )
        }
        return try result.get()
    }
}
