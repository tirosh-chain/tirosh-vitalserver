import Foundation
import Contracts

enum RuntimeControlStaticFileLookup: Equatable {
    case found(URL)
    case notFound
    case failed(String)
    case rejected(String)
}

struct RuntimeControlStaticFilePathResolver: Sendable {
    private let rootDirectory: URL
    private let fileReader: any RuntimeControlStaticFileReading

    init(
        rootDirectory: URL,
        fileReader: any RuntimeControlStaticFileReading
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileReader = fileReader
    }

    func shouldHandle(_ request: RuntimeControlHTTPRequest) -> Bool {
        request.method == .get && !isAPIRoute(request.path)
    }

    func lookup(rawPath: String) -> RuntimeControlStaticFileLookup {
        let path = normalizedPath(rawPath)
        if path == "/" || path == "/runtime-control" || path == "/runtime-control/" {
            return existingFile(rootDirectory.appendingPathComponent("index.html"))
        }

        switch decodedRelativePath(path) {
        case .root:
            return existingFile(rootDirectory.appendingPathComponent("index.html"))
        case .rejected(let reason):
            return .rejected(reason)
        case .relative(let relativePath):
            let requestedURL = rootDirectory.appendingPathComponent(relativePath).standardizedFileURL
            switch existingFile(requestedURL) {
            case .found(let existing) where isInsideRoot(existing):
                return .found(existing)
            case .found:
                return .rejected("static file path escapes root")
            case .failed(let reason):
                return .failed(reason)
            default:
                break
            }

            if URL(fileURLWithPath: relativePath).pathExtension.isEmpty {
                return existingFile(rootDirectory.appendingPathComponent("index.html"))
            }
            return .notFound
        }
    }

    private enum DecodedStaticFilePath: Equatable {
        case root
        case relative(String)
        case rejected(String)
    }

    private func decodedRelativePath(_ path: String) -> DecodedStaticFilePath {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            return .root
        }
        guard let decoded = trimmed.removingPercentEncoding else {
            return .rejected("static file path percent-decoding failed")
        }
        let components = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else {
            return .rejected("static file path contains parent directory segment")
        }
        return .relative(components.joined(separator: "/"))
    }

    private func existingFile(_ url: URL) -> RuntimeControlStaticFileLookup {
        let pathState = fileReader.pathState(at: url)
        switch pathState {
        case .file:
            return .found(url)
        case .missing, .directory:
            return .notFound
        case .inspectFailed(let reason):
            return .failed("static file path inspection failed: \(url.path) reason=\(reason)")
        case .other, .unknown:
            return .failed("static file path state is unexpected: \(url.path) state=\(pathState.rawValue)")
        }
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
}
