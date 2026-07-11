import Application
import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl

final class RuntimeControlOperationLeaseController: RuntimeOperationLeaseOwner, @unchecked Sendable {
    private let owner: any RuntimeOperationLeaseOwner

    init(owner: any RuntimeOperationLeaseOwner) {
        self.owner = owner
    }

    func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        owner.loadOperationLease()
    }

    func acquire(_ document: RuntimeOperationLeaseDocument) throws {
        try owner.acquire(document)
    }

    func heartbeat(operationId: String, heartbeatAt: String, expiresAt: String?) throws {
        try owner.heartbeat(
            operationId: operationId,
            heartbeatAt: heartbeatAt,
            expiresAt: expiresAt
        )
    }

    func release(operationId: String) throws {
        try owner.release(operationId: operationId)
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
