import Foundation

struct RuntimeControlStaticFileResponseFactory {
    func found(fileURL: URL, body: Data) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .ok,
            headers: [
                "Cache-Control": cacheControl(for: fileURL),
                "Content-Type": contentType(for: fileURL),
            ],
            body: body
        )
    }

    func notFound() -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("Not found".utf8)
        )
    }

    func readFailed(_ reason: String) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .internalServerError,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("Static file read failed: \(reason)".utf8)
        )
    }

    func badRequest(_ reason: String) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .badRequest,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("Static file request rejected: \(reason)".utf8)
        )
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "css":
            return "text/css; charset=utf-8"
        case "html":
            return "text/html; charset=utf-8"
        case "js", "mjs":
            return "text/javascript; charset=utf-8"
        case "json", "webmanifest":
            return "application/json; charset=utf-8"
        case "png":
            return "image/png"
        case "svg":
            return "image/svg+xml"
        case "ico":
            return "image/x-icon"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        default:
            return "application/octet-stream"
        }
    }

    private func cacheControl(for url: URL) -> String {
        switch url.lastPathComponent {
        case "index.html", "sw.js", "registerSW.js", "manifest.webmanifest":
            return "no-cache"
        default:
            return "public, max-age=31536000, immutable"
        }
    }
}
