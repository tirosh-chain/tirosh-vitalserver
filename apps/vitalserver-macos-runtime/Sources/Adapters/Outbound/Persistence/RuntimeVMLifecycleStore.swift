import Application
import Contracts
import Foundation
import Errors

public struct RuntimeVMLifecycleStore: @unchecked Sendable {
    public let url: URL
    public let fileStore: RuntimeFileReading & RuntimeFileWriting
    public let now: @Sendable () -> Date

    public init(
        url: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.url = url
        self.fileStore = fileStore
        self.now = now
    }

    public func load() -> RuntimeGuestDocumentLoadResult<RuntimeVMLifecycleDocument> {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .failed("VM lifecycle path inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("VM lifecycle path state is unexpected path=\(url.path) state=\(state.rawValue)")
        }
        do {
            return try .loaded(JSONDecoder().decode(RuntimeVMLifecycleDocument.self, from: fileStore.readData(url)))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public func write(
        state: RuntimeVMLifecycleState,
        operation: RuntimeOperation? = nil,
        terminalReason: RuntimeVMLifecycleTerminalReason? = nil,
        message: String? = nil,
        bootWindowSeconds: TimeInterval? = nil
    ) throws {
        let timestamp = now()
        let startedAt = try startedAtForWrite(state: state, timestamp: timestamp)
        let deadlineAt = bootWindowSeconds.map { timestamp.addingTimeInterval($0) }
        let document = RuntimeVMLifecycleDocument(
            state: state,
            operation: operation,
            startedAt: ISO8601DateFormatter().string(from: startedAt),
            updatedAt: ISO8601DateFormatter().string(from: timestamp),
            deadlineAt: deadlineAt.map { ISO8601DateFormatter().string(from: $0) },
            terminalReason: terminalReason,
            message: message
        )
        try fileStore.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileStore.writeData(try runtimeVMLifecycleDocumentEncoder().encode(document), to: url, options: .atomic)
    }

    private func startedAtForWrite(state: RuntimeVMLifecycleState, timestamp: Date) throws -> Date {
        guard state != .starting else {
            return timestamp
        }
        return try currentStartedAt(requiredFor: state)
    }

    private func currentStartedAt(requiredFor state: RuntimeVMLifecycleState) throws -> Date {
        switch load() {
        case .missing:
            throw RuntimeVMLifecycleStoreError.missingDocumentForState(state)
        case .failed(let reason):
            throw RuntimeVMLifecycleStoreError.readFailed(reason)
        case .loaded(let document):
            guard let startedAt = ISO8601DateFormatter().date(from: document.startedAt) else {
                throw RuntimeVMLifecycleStoreError.invalidStartedAt(document.startedAt)
            }
            return startedAt
        }
    }
}

private func runtimeVMLifecycleDocumentEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
