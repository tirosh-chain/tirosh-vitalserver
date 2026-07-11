import Application
import Contracts
import Foundation
import RuntimeControl

public struct FileRuntimeVMLifecycleResourceStore: RuntimeVMLifecycleResourceReading,
    RuntimeVMLifecycleResourceWriting, @unchecked Sendable
{
    private let documentURL: URL
    private let fileStore: any RuntimeFileStore
    private let fileLock: any RuntimeFileLocking
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: @Sendable () -> Date

    public init(
        documentURL: URL,
        fileStore: any RuntimeFileStore = SystemRuntimeFileStore(),
        fileLock: any RuntimeFileLocking = POSIXRuntimeFileLock(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.documentURL = documentURL
        self.fileStore = fileStore
        self.fileLock = fileLock
        self.encoder = encoder
        self.decoder = decoder
        self.now = now
    }

    public func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState {
        switch fileStore.pathState(at: documentURL) {
        case .missing:
            return .missing(readError: "Runtime Provider lifecycle document missing path=\(documentURL.path)")
        case .file:
            do {
                return .loaded(try decoder.decode(
                    RuntimeVMLifecycleDocument.self,
                    from: fileStore.readData(documentURL)
                ))
            } catch {
                return .failed(
                    readError: "Runtime Provider lifecycle document read failed path=\(documentURL.path) reason=\(error)"
                )
            }
        case .directory:
            return .failed(
                readError: "Runtime Provider lifecycle path is a directory path=\(documentURL.path)"
            )
        case .other(let value):
            return .failed(
                readError: "Runtime Provider lifecycle path has unsupported type path=\(documentURL.path) type=\(value)"
            )
        case .inspectFailed(let reason):
            return .failed(
                readError: "Runtime Provider lifecycle path inspection failed path=\(documentURL.path) reason=\(reason)"
            )
        case .unknown(let value):
            return .failed(
                readError: "Runtime Provider lifecycle path state is unknown path=\(documentURL.path) state=\(value)"
            )
        }
    }

    @discardableResult
    public func writeVMLifecycleResource(
        state: RuntimeVMLifecycleState,
        operation: RuntimeOperation? = nil,
        terminalReason: RuntimeVMLifecycleTerminalReason? = nil,
        message: String? = nil,
        bootWindowSeconds: TimeInterval? = nil
    ) throws -> RuntimeVMLifecycleResourceState {
        try fileLock.withExclusiveLock(for: documentURL) {
            let timestamp = now()
            let startedAt = try startedAtForWrite(state: state, timestamp: timestamp)
            let deadlineAt = bootWindowSeconds.map { timestamp.addingTimeInterval($0) }
            return try persist(RuntimeVMLifecycleDocument(
                state: state,
                operation: operation,
                startedAt: Self.timestamp(startedAt),
                updatedAt: Self.timestamp(timestamp),
                deadlineAt: deadlineAt.map(Self.timestamp),
                terminalReason: terminalReason,
                message: message
            ))
        }
    }

    @discardableResult
    public func putVMLifecycleResource(
        _ document: RuntimeVMLifecycleDocument
    ) throws -> RuntimeVMLifecycleResourceState {
        try fileLock.withExclusiveLock(for: documentURL) {
            try persist(document)
        }
    }

    private func persist(
        _ document: RuntimeVMLifecycleDocument
    ) throws -> RuntimeVMLifecycleResourceState {
        try fileStore.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileStore.writeData(
            encoder.encode(document),
            to: documentURL,
            options: .atomic
        )
        return .loaded(document)
    }

    private func startedAtForWrite(
        state: RuntimeVMLifecycleState,
        timestamp: Date
    ) throws -> Date {
        guard state != .starting else {
            return timestamp
        }
        let current = loadVMLifecycleResource()
        switch current.state {
        case .loaded:
            guard let document = current.document else {
                throw RuntimeVMLifecycleResourceWriteError.readFailed(
                    "Runtime Provider lifecycle resource loaded without document"
                )
            }
            guard let startedAt = ISO8601DateFormatter().date(from: document.startedAt) else {
                throw RuntimeVMLifecycleResourceWriteError.invalidStartedAt(document.startedAt)
            }
            return startedAt
        case .missing:
            throw RuntimeVMLifecycleResourceWriteError.missingDocumentForState(state)
        case .unavailable, .failed:
            throw RuntimeVMLifecycleResourceWriteError.readFailed(
                current.readError ?? "Runtime Provider lifecycle read failed state=\(current.state.rawValue)"
            )
        }
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
