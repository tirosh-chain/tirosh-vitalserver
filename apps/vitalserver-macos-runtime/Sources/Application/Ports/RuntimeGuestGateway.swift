import Contracts
import Foundation
import Errors

public typealias RuntimeGuestDocumentLoadResult<Document> = Contracts.RuntimeGuestDocumentLoadResult<Document>

public protocol RuntimeGuestGateway {
    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>
    func loadServiceStackStatusDocument() -> RuntimeGuestDocumentLoadResult<ServiceStackStatusDocument>
    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>
    func removeUpdateActivationResult() throws
    func writeUpdateActivationRequest(_ request: RuntimeGuestActivationRequest) throws
    func loadUpdateActivationResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateActivationResultDocument>
    func removeUpdateShutdownResult() throws
    func clearUpdateShutdownPreparation() throws
    func writeUpdateShutdownRequest(_ request: RuntimeGuestShutdownRequest) throws
    func loadUpdateShutdownResultDocument() -> RuntimeGuestDocumentLoadResult<GuestUpdateShutdownResultDocument>
    func removeDatastoreRepairResult() throws
    func writeDatastoreRepairRequest(_ request: RuntimeDatastoreRepairRequest) throws
    func loadDatastoreRepairResultDocument() -> RuntimeGuestDocumentLoadResult<DatastoreRepairResultDocument>
    func removeGuestComposeReconcileResult() throws
    func writeGuestComposeReconcileRequest(_ request: RuntimeGuestComposeReconcileRequest) throws
    func loadGuestComposeReconcileResultDocument() -> RuntimeGuestDocumentLoadResult<GuestComposeReconcileResultDocument>
    func removeRedisRestoreResult() throws
    func writeRedisRestoreRequest(_ request: RedisRestoreRequestDocument) throws
    func loadRedisRestoreResultDocument() -> RuntimeGuestDocumentLoadResult<RedisRestoreResultDocument>
}

public extension RuntimeGuestGateway {
    func loadServiceStackStatusDocument() -> RuntimeGuestDocumentLoadResult<ServiceStackStatusDocument> {
        .failed("service stack status gateway is unavailable")
    }

    func removeGuestComposeReconcileResult() throws {
        throw RuntimeGuestCapabilityCheckError.missingCapability("reconcile-compose")
    }

    func writeGuestComposeReconcileRequest(_ request: RuntimeGuestComposeReconcileRequest) throws {
        throw RuntimeGuestCapabilityCheckError.missingCapability("reconcile-compose")
    }

    func loadGuestComposeReconcileResultDocument() -> RuntimeGuestDocumentLoadResult<GuestComposeReconcileResultDocument> {
        .failed("guest compose reconcile gateway is unavailable")
    }

    func removeRedisRestoreResult() throws {
        throw RuntimeGuestCapabilityCheckError.missingCapability("redis-restore")
    }

    func writeRedisRestoreRequest(_ request: RedisRestoreRequestDocument) throws {
        throw RuntimeGuestCapabilityCheckError.missingCapability("redis-restore")
    }

    func loadRedisRestoreResultDocument() -> RuntimeGuestDocumentLoadResult<RedisRestoreResultDocument> {
        .failed("redis restore gateway is unavailable")
    }
}
