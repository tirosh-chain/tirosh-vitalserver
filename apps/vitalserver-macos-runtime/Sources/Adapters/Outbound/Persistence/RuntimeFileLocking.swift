import Darwin
import Foundation

public protocol RuntimeFileLocking {
    func withExclusiveLock<T>(for url: URL, _ body: () throws -> T) throws -> T
}

public struct POSIXRuntimeFileLock: RuntimeFileLocking {
    public init() {}

    public func withExclusiveLock<T>(for url: URL, _ body: () throws -> T) throws -> T {
        let lockURL = url.appendingPathExtension("lock")
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            guard FileManager.default.createFile(atPath: lockURL.path, contents: nil) else {
                throw RuntimeFileLockError.lockFailed(
                    path: lockURL.path,
                    reason: "lock file create failed"
                )
            }
        }
        let descriptor = Darwin.open(lockURL.path, O_RDWR)
        guard descriptor >= 0 else {
            throw RuntimeFileLockError.lockFailed(
                path: lockURL.path,
                reason: String(cString: strerror(errno))
            )
        }
        defer {
            Darwin.close(descriptor)
        }
        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
            throw RuntimeFileLockError.lockFailed(
                path: lockURL.path,
                reason: String(cString: strerror(errno))
            )
        }
        do {
            let result = try body()
            if Darwin.lockf(descriptor, F_ULOCK, 0) != 0 {
                throw RuntimeFileLockError.lockFailed(
                    path: lockURL.path,
                    reason: String(cString: strerror(errno))
                )
            }
            return result
        } catch {
            _ = Darwin.lockf(descriptor, F_ULOCK, 0)
            throw error
        }
    }
}

public enum RuntimeFileLockError: Error, Equatable, CustomStringConvertible {
    case lockFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .lockFailed(let path, let reason):
            return "runtime file lock failed path=\(path) reason=\(reason)"
        }
    }
}
