import Application
import Contracts
import Foundation
import RuntimeControl

public struct SQLiteRuntimeVMLifecycleResourceStore:
    RuntimeVMLifecycleResourceReading,
    RuntimeVMLifecycleResourceWriting,
    @unchecked Sendable
{
    private let repository: SQLiteRuntimeVMLifecycleStateRepository
    private let now: @Sendable () -> Date
    private let operationID: @Sendable () -> String
    private let bootID: @Sendable () -> String

    public init(
        databaseURL: URL,
        transitionDecider: any RuntimeVMLifecycleTransitionDeciding,
        now: @escaping @Sendable () -> Date = Date.init,
        operationID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        bootID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.repository = SQLiteRuntimeVMLifecycleStateRepository(
            databaseURL: databaseURL,
            transitionDecider: transitionDecider
        )
        self.now = now
        self.operationID = operationID
        self.bootID = bootID
    }

    public func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState {
        switch repository.loadVMLifecycleState() {
        case .missing:
            return .missing(readError: "VM lifecycle SQLite state is missing")
        case .loaded(let record):
            return .loaded(record.document)
        case .failed(let reason):
            return .failed(readError: reason)
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
        let timestamp = now()
        let timestampText = Self.timestamp(timestamp)
        let current = try currentRecord()
        let document: RuntimeVMLifecycleDocument
        let expectedRevision: Int?
        if state == .starting {
            document = RuntimeVMLifecycleDocument(
                state: state,
                operation: operation,
                operationID: operationID(),
                bootID: bootID(),
                startedAt: timestampText,
                updatedAt: timestampText,
                deadlineAt: bootWindowSeconds.map { Self.timestamp(timestamp.addingTimeInterval($0)) },
                terminalReason: terminalReason,
                message: message
            )
            expectedRevision = current?.revision
        } else {
            guard let current else {
                throw RuntimeVMLifecycleResourceWriteError.missingDocumentForState(state)
            }
            document = RuntimeVMLifecycleDocument(
                state: state,
                operation: operation ?? current.document.operation,
                operationID: current.document.operationID,
                bootID: current.document.bootID,
                startedAt: current.document.startedAt,
                updatedAt: timestampText,
                deadlineAt: bootWindowSeconds.map { Self.timestamp(timestamp.addingTimeInterval($0)) },
                terminalReason: terminalReason,
                message: message
            )
            expectedRevision = current.revision
        }
        return try put(document, expectedRevision: expectedRevision)
    }

    @discardableResult
    public func putVMLifecycleResource(
        _ document: RuntimeVMLifecycleDocument
    ) throws -> RuntimeVMLifecycleResourceState {
        let current = try currentRecord()
        return try put(document, expectedRevision: current?.revision)
    }

    private func put(
        _ document: RuntimeVMLifecycleDocument,
        expectedRevision: Int?
    ) throws -> RuntimeVMLifecycleResourceState {
        let saved = try repository.saveVMLifecycleState(RuntimeVMLifecycleStateMutation(
            document: document,
            expectedRevision: expectedRevision
        ))
        return .loaded(saved.document)
    }

    private func currentRecord() throws -> RuntimeVMLifecycleStateRecord? {
        switch repository.loadVMLifecycleState() {
        case .missing:
            return nil
        case .loaded(let record):
            return record
        case .failed(let reason):
            throw RuntimeVMLifecycleResourceWriteError.readFailed(reason)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
