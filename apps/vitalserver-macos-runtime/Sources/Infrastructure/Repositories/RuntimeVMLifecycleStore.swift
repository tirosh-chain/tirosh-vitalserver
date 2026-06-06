import Application
import Contracts
import Foundation

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
        guard fileStore.fileExists(url) else {
            return .missing
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
        let startedAt = state == .starting ? timestamp : (currentStartedAt() ?? timestamp)
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

    private func currentStartedAt() -> Date? {
        guard case .loaded(let document) = load() else {
            return nil
        }
        return ISO8601DateFormatter().date(from: document.startedAt)
    }
}

private func runtimeVMLifecycleDocumentEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}
