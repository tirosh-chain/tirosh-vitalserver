import Contracts
import Foundation
import Errors

public typealias RuntimeGuestDocumentLoadResult<Document> = Contracts.RuntimeGuestDocumentLoadResult<Document>

public protocol RuntimeGuestGateway {
    func loadRuntimeStateDocument() -> RuntimeGuestDocumentLoadResult<GuestRuntimeStateDocument>
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
    func removeRedisRestoreResult() throws
    func writeRedisRestoreRequest(_ request: RedisRestoreRequestDocument) throws
    func loadRedisRestoreResultDocument() -> RuntimeGuestDocumentLoadResult<RedisRestoreResultDocument>
}

public extension RuntimeGuestGateway {
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
