import Contracts

public protocol RuntimeGuestMaintenanceCommandControlling: Sendable {
    func createPostgresBackup(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func restorePostgresBackup(
        archive: String,
        restartRuntime: Bool,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func createRedisBackup(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func restoreRedisBackup(
        archive: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    /// Validates the Guest operation identity while preserving its reported state.
    func requestDatastoreRepair(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func repairDatastore(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func activateUpdate(
        requestId: String,
        version: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func prepareUpdateShutdown(
        requestId: String,
        version: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation

    func requestGuestPoweroff(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation
}
