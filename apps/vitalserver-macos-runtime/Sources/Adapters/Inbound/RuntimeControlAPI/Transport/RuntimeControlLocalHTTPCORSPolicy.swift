import Foundation

struct RuntimeControlLocalHTTPCORSPolicy {
    func headers(for request: RuntimeControlHTTPRequest) -> [String: String] {
        guard let origin = headerValue("Origin", in: request.headers),
              isAllowedBrowserOrigin(origin) else {
            return [:]
        }

        return [
            "Access-Control-Allow-Headers": "Accept, Content-Type, X-Runtime-Control-Token",
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Max-Age": "600",
            "Vary": "Origin",
        ]
    }

    private func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    private func isAllowedBrowserOrigin(_ origin: String) -> Bool {
        guard let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased() else {
            return false
        }

        return host == "localhost"
            || host == "::1"
            || host == "0:0:0:0:0:0:0:1"
            || host.hasPrefix("127.")
    }
}
