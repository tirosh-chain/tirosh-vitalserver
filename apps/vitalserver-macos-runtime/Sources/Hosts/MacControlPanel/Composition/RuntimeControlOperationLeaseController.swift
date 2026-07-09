import Application
import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl

final class RuntimeControlOperationLeaseController: RuntimeOperationLeaseOwner, @unchecked Sendable {
    private let lock = NSLock()
    private var document: RuntimeOperationLeaseDocument?

    func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        withLock {
            guard let document else {
                return .missing
            }
            return .loaded(document)
        }
    }

    func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        try withLock {
            if let existing = self.document {
                throw RuntimeOperationLeaseOwnerError.existingOperation(
                    operationId: existing.operationId,
                    operation: existing.operation.rawValue
                )
            }
            self.document = document
        }
    }

    func heartbeat(operationId: String, heartbeatAt: String, expiresAt: String?) throws {
        try withLock {
            guard let existing = document else {
                throw RuntimeOperationLeaseOwnerError.readFailed(
                    "runtime operation lease is missing during heartbeat"
                )
            }
            guard existing.operationId == operationId else {
                throw RuntimeOperationLeaseOwnerError.operationIdMismatch(
                    expected: operationId,
                    actual: existing.operationId
                )
            }
            document = RuntimeOperationLeaseDocument(
                schemaVersion: existing.schemaVersion,
                operationId: existing.operationId,
                operation: existing.operation,
                ownerPID: existing.ownerPID,
                startedAt: existing.startedAt,
                heartbeatAt: heartbeatAt,
                expiresAt: expiresAt,
                message: existing.message
            )
        }
    }

    func release(operationId: String) throws {
        try withLock {
            guard let existing = document else {
                return
            }
            guard existing.operationId == operationId else {
                throw RuntimeOperationLeaseOwnerError.operationIdMismatch(
                    expected: operationId,
                    actual: existing.operationId
                )
            }
            document = nil
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

@MainActor
extension RuntimeControlOperationLeaseController: RuntimeOperationLeaseMutationClient {
    func acquireOperationLease(
        _ document: RuntimeOperationLeaseDocument
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        try acquire(document)
        return RuntimeOperationLeaseMutationResponse(
            operationId: document.operationId,
            state: .acquired
        )
    }

    func heartbeatOperationLease(
        operationId: String,
        heartbeatAt: String,
        expiresAt: String?
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        try heartbeat(
            operationId: operationId,
            heartbeatAt: heartbeatAt,
            expiresAt: expiresAt
        )
        return RuntimeOperationLeaseMutationResponse(
            operationId: operationId,
            state: .heartbeatRecorded
        )
    }

    func releaseOperationLease(
        operationId: String
    ) async throws -> RuntimeOperationLeaseMutationResponse {
        try release(operationId: operationId)
        return RuntimeOperationLeaseMutationResponse(
            operationId: operationId,
            state: .released
        )
    }
}
