import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl

final class RuntimeControlVMLifecycleController: RuntimeVMLifecycleResourceReading,
    RuntimeVMLifecycleResourceWriting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let now: @Sendable () -> Date
    private var document: RuntimeVMLifecycleDocument?

    init(
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.document = nil
        self.now = now
    }

    func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState {
        withLock {
            guard let document else {
                return .missing(readError: "VM lifecycle document missing")
            }
            return .loaded(document)
        }
    }

    @discardableResult
    func writeVMLifecycleResource(
        state: RuntimeVMLifecycleState,
        operation: RuntimeOperation? = nil,
        terminalReason: RuntimeVMLifecycleTerminalReason? = nil,
        message: String? = nil,
        bootWindowSeconds: TimeInterval? = nil
    ) throws -> RuntimeVMLifecycleResourceState {
        try withLock {
            let timestamp = now()
            let startedAt = try startedAtForWrite(state: state, timestamp: timestamp)
            let deadlineAt = bootWindowSeconds.map { timestamp.addingTimeInterval($0) }
            let next = RuntimeVMLifecycleDocument(
                state: state,
                operation: operation,
                startedAt: ISO8601DateFormatter().string(from: startedAt),
                updatedAt: ISO8601DateFormatter().string(from: timestamp),
                deadlineAt: deadlineAt.map { ISO8601DateFormatter().string(from: $0) },
                terminalReason: terminalReason,
                message: message
            )
            document = next
            return .loaded(next)
        }
    }

    @discardableResult
    private func putVMLifecycleResourceSync(_ document: RuntimeVMLifecycleDocument) -> RuntimeVMLifecycleResourceState {
        withLock {
            self.document = document
            return .loaded(document)
        }
    }

    private func startedAtForWrite(
        state: RuntimeVMLifecycleState,
        timestamp: Date
    ) throws -> Date {
        guard state != .starting else {
            return timestamp
        }
        guard let document else {
            throw RuntimeVMLifecycleResourceWriteError.missingDocumentForState(state)
        }
        guard let startedAt = ISO8601DateFormatter().date(from: document.startedAt) else {
            throw RuntimeVMLifecycleResourceWriteError.invalidStartedAt(document.startedAt)
        }
        return startedAt
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

@MainActor
extension RuntimeControlVMLifecycleController: RuntimeVMLifecycleResourceClient {
    func loadVMLifecycleResource() async throws -> RuntimeVMLifecycleResourceState {
        (self as RuntimeVMLifecycleResourceReading).loadVMLifecycleResource()
    }

    func putVMLifecycleResource(
        _ document: RuntimeVMLifecycleDocument
    ) async throws -> RuntimeVMLifecycleResourceState {
        putVMLifecycleResourceSync(document)
    }
}
