import Application
import Contracts
import Foundation
import Errors

public struct RuntimeContainerLogsMetadataReader {
    private let url: URL
    private let fileStore: RuntimeFileReading

    public init(url: URL, fileStore: RuntimeFileReading) {
        self.url = url
        self.fileStore = fileStore
    }

    public func read() -> RuntimeContainerLogsMetadata {
        let pathState = fileStore.pathState(at: url)
        switch pathState {
        case .file:
            break
        case .missing:
            return RuntimeContainerLogsMetadata(present: false, bytes: nil, updatedAt: nil, error: nil)
        case .inspectFailed(let reason):
            return RuntimeContainerLogsMetadata(
                present: false,
                bytes: nil,
                updatedAt: nil,
                error: "container logs path inspection failed path=\(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            return RuntimeContainerLogsMetadata(
                present: false,
                bytes: nil,
                updatedAt: nil,
                error: "container logs path state is unexpected path=\(url.path) state=\(pathState.rawValue)"
            )
        }

        var errorTokens: [String] = []
        let bytes: UInt64?
        do {
            bytes = try fileStore.fileSize(url)
        } catch {
            bytes = nil
            errorTokens.append("size-read-failed reason=\(error.localizedDescription)")
        }

        let updatedAt: String?
        do {
            updatedAt = ISO8601DateFormatter().string(from: try fileStore.modificationDate(url))
        } catch {
            updatedAt = nil
            errorTokens.append("mtime-read-failed reason=\(error.localizedDescription)")
        }

        return RuntimeContainerLogsMetadata(
            present: true,
            bytes: bytes,
            updatedAt: updatedAt,
            error: errorTokens.isEmpty ? nil : errorTokens.joined(separator: ",")
        )
    }
}

public struct RuntimeFileModifiedAtReader {
    private let url: URL
    private let fileStore: RuntimeFileReading

    public init(url: URL, fileStore: RuntimeFileReading) {
        self.url = url
        self.fileStore = fileStore
    }

    public func read() -> RuntimeFileModifiedAtReadResult {
        let pathState = fileStore.pathState(at: url)
        switch pathState {
        case .file:
            break
        case .missing:
            return RuntimeFileModifiedAtReadResult(
                updatedAt: nil,
                readError: "file modified-at path missing path=\(url.path)"
            )
        case .inspectFailed(let reason):
            return RuntimeFileModifiedAtReadResult(
                updatedAt: nil,
                readError: "file modified-at path inspection failed path=\(url.path) reason=\(reason)"
            )
        case .directory, .other, .unknown:
            return RuntimeFileModifiedAtReadResult(
                updatedAt: nil,
                readError: "file modified-at path state is unexpected path=\(url.path) state=\(pathState.rawValue)"
            )
        }

        do {
            return RuntimeFileModifiedAtReadResult(
                updatedAt: ISO8601DateFormatter().string(from: try fileStore.modificationDate(url)),
                readError: nil
            )
        } catch {
            return RuntimeFileModifiedAtReadResult(
                updatedAt: nil,
                readError: "mtime-read-failed path=\(url.path) reason=\(error.localizedDescription)"
            )
        }
    }
}
