import Application
import Contracts
import Darwin
import Errors
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
                throw RuntimeOperationLeaseRepositoryError.lockFailed(
                    path: lockURL.path,
                    reason: "lock file create failed"
                )
            }
        }
        let descriptor = Darwin.open(lockURL.path, O_RDWR)
        guard descriptor >= 0 else {
            throw RuntimeOperationLeaseRepositoryError.lockFailed(
                path: lockURL.path,
                reason: String(cString: strerror(errno))
            )
        }
        defer {
            Darwin.close(descriptor)
        }
        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
            throw RuntimeOperationLeaseRepositoryError.lockFailed(
                path: lockURL.path,
                reason: String(cString: strerror(errno))
            )
        }
        do {
            let result = try body()
            if Darwin.lockf(descriptor, F_ULOCK, 0) != 0 {
                throw RuntimeOperationLeaseRepositoryError.lockFailed(
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

public struct JSONFileRuntimeOperationLeaseRepository: RuntimeOperationLeaseRepository {
    public let url: URL
    private let fileStore: RuntimeFileReading & RuntimeFileWriting
    private let fileLock: RuntimeFileLocking

    public init(
        url: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore(),
        fileLock: RuntimeFileLocking = POSIXRuntimeFileLock()
    ) {
        self.url = url
        self.fileStore = fileStore
        self.fileLock = fileLock
    }

    public func loadResult() -> RuntimeOperationLeaseLoadResult {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .failed("runtime operation lease path inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("runtime operation lease path state is unexpected path=\(url.path) state=\(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(RuntimeOperationLeaseDocument.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileLock.withExclusiveLock(for: url) {
            switch loadResult() {
            case .missing:
                break
            case .loaded(let existing):
                throw RuntimeOperationLeaseRepositoryError.existingOperation(
                    operationId: existing.operationId,
                    operation: existing.operation.rawValue
                )
            case .failed(let reason):
                throw RuntimeOperationLeaseRepositoryError.readFailed(reason)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try fileStore.writeData(data, to: url, options: .atomic)
        }
    }

    public func heartbeat(operationId: String, heartbeatAt: String, expiresAt: String?) throws {
        try fileLock.withExclusiveLock(for: url) {
            let existing: RuntimeOperationLeaseDocument
            switch loadResult() {
            case .missing:
                throw RuntimeOperationLeaseRepositoryError.readFailed(
                    "runtime operation lease is missing during heartbeat"
                )
            case .loaded(let document):
                existing = document
            case .failed(let reason):
                throw RuntimeOperationLeaseRepositoryError.readFailed(reason)
            }

            guard existing.operationId == operationId else {
                throw RuntimeOperationLeaseRepositoryError.operationIdMismatch(
                    expected: operationId,
                    actual: existing.operationId
                )
            }

            let updated = RuntimeOperationLeaseDocument(
                schemaVersion: existing.schemaVersion,
                operationId: existing.operationId,
                operation: existing.operation,
                ownerPID: existing.ownerPID,
                startedAt: existing.startedAt,
                heartbeatAt: heartbeatAt,
                expiresAt: expiresAt,
                message: existing.message
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try fileStore.writeData(try encoder.encode(updated), to: url, options: .atomic)
        }
    }

    public func release(operationId: String) throws {
        try fileLock.withExclusiveLock(for: url) {
            switch loadResult() {
            case .missing:
                return
            case .loaded(let existing):
                guard existing.operationId == operationId else {
                    throw RuntimeOperationLeaseRepositoryError.operationIdMismatch(
                        expected: operationId,
                        actual: existing.operationId
                    )
                }
                try fileStore.removeItem(at: url)
            case .failed(let reason):
                throw RuntimeOperationLeaseRepositoryError.readFailed(reason)
            }
        }
    }
}
