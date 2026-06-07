import Application
import Contracts
import Foundation
import RuntimeControl
import Errors

struct RuntimeDataDirectoryStatsReader {
    let fileStore: RuntimeFileStore

    func read(path: String) -> RuntimeDataDirectoryStatsRead {
        do {
            return try readStats(path: path)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func readStats(path: String) throws -> RuntimeDataDirectoryStatsRead {
        let root = URL(fileURLWithPath: path)
        let rootState = fileStore.pathState(at: root)
        switch rootState {
        case .directory:
            break
        case .missing:
            return .missing(path: root.path)
        case .file, .other, .unknown:
            throw RuntimeDataDirectoryStatsReadError.unexpectedPathState(
                path: root.path,
                state: rootState.rawValue
            )
        case .inspectFailed(let reason):
            throw RuntimeDataDirectoryStatsReadError.pathInspectionFailed(path: root.path, reason: reason)
        }
        let stats = try directoryStats(root)
        return .loaded(RuntimeDataDirectoryStats(fileCount: stats.fileCount, sizeBytes: Int64(stats.sizeBytes)))
    }

    private func directoryStats(_ directory: URL) throws -> (fileCount: Int, sizeBytes: UInt64) {
        let contents = try fileStore.contentsOfDirectory(at: directory, skipsHiddenFiles: true)

        var fileCount = 0
        var sizeBytes: UInt64 = 0
        for url in contents {
            let pathState = fileStore.pathState(at: url)
            switch pathState {
            case .directory:
                let nested = try directoryStats(url)
                fileCount += nested.fileCount
                sizeBytes += nested.sizeBytes
            case .file:
                fileCount += 1
                sizeBytes += try fileStore.fileSize(url)
            case .missing:
                throw RuntimeDataDirectoryStatsReadError.listedPathMissing(path: url.path)
            case .other, .unknown:
                throw RuntimeDataDirectoryStatsReadError.unexpectedPathState(
                    path: url.path,
                    state: pathState.rawValue
                )
            case .inspectFailed(let reason):
                throw RuntimeDataDirectoryStatsReadError.pathInspectionFailed(path: url.path, reason: reason)
            }
        }
        return (fileCount, sizeBytes)
    }
}

enum RuntimeDataDirectoryStatsReadError: Error, CustomStringConvertible {
    case pathInspectionFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
    case listedPathMissing(path: String)

    var description: String {
        switch self {
        case .pathInspectionFailed(let path, let reason):
            "data directory path inspection failed path=\(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            "data directory path state is unexpected path=\(path) state=\(state)"
        case .listedPathMissing(let path):
            "data directory listed path is missing during traversal path=\(path)"
        }
    }
}
