import Application
import Contracts
import Foundation

public struct JSONFileRuntimeOperationLeaseRepository: RuntimeOperationLeaseOwner, @unchecked Sendable {
    public let url: URL
    private let fileStore: any RuntimeFileStore
    private let fileLock: any RuntimeFileLocking
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        url: URL,
        fileStore: any RuntimeFileStore = SystemRuntimeFileStore(),
        fileLock: any RuntimeFileLocking = POSIXRuntimeFileLock(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.url = url
        self.fileStore = fileStore
        self.fileLock = fileLock
        self.encoder = encoder
        self.decoder = decoder
    }

    public func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        switch fileStore.pathState(at: url) {
        case .missing:
            return .missing
        case .file:
            do {
                return .loaded(try decoder.decode(
                    RuntimeOperationLeaseDocument.self,
                    from: fileStore.readData(url)
                ))
            } catch {
                return .failed(
                    "runtime operation lease read failed path=\(url.path) reason=\(error)"
                )
            }
        case .directory:
            return .failed("runtime operation lease path is a directory path=\(url.path)")
        case .other(let value):
            return .failed(
                "runtime operation lease path has unsupported type path=\(url.path) type=\(value)"
            )
        case .inspectFailed(let reason):
            return .failed(
                "runtime operation lease path inspection failed path=\(url.path) reason=\(reason)"
            )
        case .unknown(let value):
            return .failed(
                "runtime operation lease path state is unknown path=\(url.path) state=\(value)"
            )
        }
    }

    public func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        try fileStore.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileLock.withExclusiveLock(for: url) {
            switch loadOperationLease() {
            case .missing:
                break
            case .loaded(let existing):
                throw RuntimeOperationLeaseOwnerError.existingOperation(
                    operationId: existing.operationId,
                    operation: existing.operation.rawValue
                )
            case .failed(let reason):
                throw RuntimeOperationLeaseOwnerError.readFailed(reason)
            }
            try persist(document)
        }
    }

    public func heartbeat(
        operationId: String,
        heartbeatAt: String,
        expiresAt: String?
    ) throws {
        try fileLock.withExclusiveLock(for: url) {
            let existing = try requiredDocument(during: "heartbeat")
            guard existing.operationId == operationId else {
                throw RuntimeOperationLeaseOwnerError.operationIdMismatch(
                    expected: operationId,
                    actual: existing.operationId
                )
            }
            try persist(RuntimeOperationLeaseDocument(
                schemaVersion: existing.schemaVersion,
                operationId: existing.operationId,
                operation: existing.operation,
                ownerPID: existing.ownerPID,
                startedAt: existing.startedAt,
                heartbeatAt: heartbeatAt,
                expiresAt: expiresAt,
                message: existing.message
            ))
        }
    }

    public func release(operationId: String) throws {
        try fileLock.withExclusiveLock(for: url) {
            switch loadOperationLease() {
            case .missing:
                return
            case .loaded(let existing):
                guard existing.operationId == operationId else {
                    throw RuntimeOperationLeaseOwnerError.operationIdMismatch(
                        expected: operationId,
                        actual: existing.operationId
                    )
                }
                try fileStore.removeItem(at: url)
            case .failed(let reason):
                throw RuntimeOperationLeaseOwnerError.readFailed(reason)
            }
        }
    }

    private func requiredDocument(during operation: String) throws -> RuntimeOperationLeaseDocument {
        switch loadOperationLease() {
        case .loaded(let document):
            return document
        case .missing:
            throw RuntimeOperationLeaseOwnerError.readFailed(
                "runtime operation lease is missing during \(operation)"
            )
        case .failed(let reason):
            throw RuntimeOperationLeaseOwnerError.readFailed(reason)
        }
    }

    private func persist(_ document: RuntimeOperationLeaseDocument) throws {
        try fileStore.writeData(
            encoder.encode(document),
            to: url,
            options: .atomic
        )
    }
}
