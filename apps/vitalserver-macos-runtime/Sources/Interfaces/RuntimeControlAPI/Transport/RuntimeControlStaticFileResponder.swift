import Foundation

public struct RuntimeControlStaticFileResponder: Sendable {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    public func response(for request: RuntimeControlHTTPRequest) -> RuntimeControlHTTPResponse? {
        guard request.method == .get else {
            return nil
        }
        guard !isAPIRoute(request.path) else {
            return nil
        }

        guard let fileURL = fileURL(for: request.path) else {
            return notFoundResponse()
        }

        do {
            let body = try Data(contentsOf: fileURL)
            return RuntimeControlHTTPResponse(
                status: .ok,
                headers: [
                    "Cache-Control": cacheControl(for: fileURL),
                    "Content-Type": contentType(for: fileURL),
                ],
                body: body
            )
        } catch {
            return notFoundResponse()
        }
    }

    private func fileURL(for rawPath: String) -> URL? {
        let path = normalizedPath(rawPath)
        if path == "/" || path == "/runtime-control" || path == "/runtime-control/" {
            return existingFile(rootDirectory.appendingPathComponent("index.html"))
        }

        guard let relativePath = decodedRelativePath(path), !relativePath.isEmpty else {
            return existingFile(rootDirectory.appendingPathComponent("index.html"))
        }

        let requestedURL = rootDirectory.appendingPathComponent(relativePath).standardizedFileURL
        if let existing = existingFile(requestedURL), isInsideRoot(existing) {
            return existing
        }

        if URL(fileURLWithPath: relativePath).pathExtension.isEmpty {
            return existingFile(rootDirectory.appendingPathComponent("index.html"))
        }
        return nil
    }

    private func decodedRelativePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            return ""
        }
        guard let decoded = trimmed.removingPercentEncoding else {
            return nil
        }
        let components = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else {
            return nil
        }
        return components.joined(separator: "/")
    }

    private func existingFile(_ url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return nil
        }
        return url
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootDirectory.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private func normalizedPath(_ path: String) -> String {
        guard let queryIndex = path.firstIndex(of: "?") else {
            return path
        }
        return String(path[..<queryIndex])
    }

    private func isAPIRoute(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return normalized == RuntimeControlDevConsoleDocument.path
            || normalized.hasPrefix("/runtime/")
            || normalized.hasPrefix("/vitaldb/")
            || normalized.hasPrefix("/host/")
            || normalized.hasPrefix("/dev/")
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

    private func notFoundResponse() -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("Not found".utf8)
        )
    }
}
