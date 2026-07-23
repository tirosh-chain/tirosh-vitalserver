import Contracts
import Errors
import Application
import XCTest

final class RuntimeGuestMaintenanceControlUseCaseTests: XCTestCase {
    func testCreatePostgresBackupReturnsDatabaseProof() throws {
        let gateway = GuestMaintenanceGateway(
            operation: postgresBackupOperation(
                result: RuntimeGuestControlOperationResult(
                    archive: "/mnt/tirosh/backups/postgres/postgres.tar.gz",
                    databaseId: "cluster:vitalserver",
                    alembicRevisions: ["0002_recorder_observability_expectations"]
                )
            )
        )

        let operation = try RuntimeGuestMaintenanceControlUseCase()
            .createPostgresBackup(gateway: gateway)

        XCTAssertEqual(operation.operationId, "postgres-backup-1")
        XCTAssertEqual(operation.command, .postgresBackup)
        XCTAssertEqual(operation.result?.databaseId, "cluster:vitalserver")
        XCTAssertEqual(
            operation.result?.alembicRevisions,
            ["0002_recorder_observability_expectations"]
        )
    }

    func testRestorePostgresBackupReturnsCompletedGuestOperation() throws {
        let archive = "/mnt/tirosh/backups/postgres/postgres.tar.gz"
        let gateway = GuestMaintenanceGateway(
            operation: postgresRestoreOperation(
                result: RuntimeGuestControlOperationResult(
                    restoredArchive: archive,
                    databaseId: "cluster:vitalserver",
                    alembicRevisions: ["0002_recorder_observability_expectations"],
                    runtimeRestarted: false
                )
            )
        )

        let operation = try RuntimeGuestMaintenanceControlUseCase()
            .restorePostgresBackup(
                archive: archive,
                restartRuntime: false,
                gateway: gateway
            )

        XCTAssertEqual(operation.operationId, "postgres-restore-1")
        XCTAssertEqual(operation.command, .postgresRestore)
        XCTAssertEqual(operation.result?.restoredArchive, archive)
        XCTAssertEqual(operation.result?.runtimeRestarted, false)
    }

    func testCreateRedisBackupReturnsCompletedGuestOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: redisBackupOperation(
                result: RuntimeGuestControlOperationResult(
                    archive: "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
                )
            )
        )

        let operation = try RuntimeGuestMaintenanceControlUseCase()
            .createRedisBackup(gateway: gateway)

        XCTAssertEqual(operation.operationId, "redis-backup-1")
        XCTAssertEqual(operation.command, .redisBackup)
        XCTAssertEqual(operation.result?.archive, "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz")
    }

    func testCreateRedisBackupRejectsFailedOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: redisBackupOperation(
                state: .failed,
                failure: RuntimeGuestControlOperationFailure(
                    kind: "redis-volume-mount-missing",
                    message: "redis volume mount is missing"
                )
            )
        )

        XCTAssertThrowsError(
            try RuntimeGuestMaintenanceControlUseCase().createRedisBackup(gateway: gateway)
        ) { error in
            guard case .operationFailed(let message) = error as? RuntimeServiceControlError else {
                return XCTFail("Expected RuntimeServiceControlError")
            }
            XCTAssertTrue(message.contains("redis-volume-mount-missing"))
        }
    }

    func testCreateRedisBackupRejectsInterruptedOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: redisBackupOperation(
                state: .interrupted,
                failure: RuntimeGuestControlOperationFailure(
                    kind: "controllerRestarted",
                    message: "Runtime Controller restarted before the operation outcome was known."
                )
            )
        )

        XCTAssertThrowsError(
            try RuntimeGuestMaintenanceControlUseCase().createRedisBackup(gateway: gateway)
        ) { error in
            guard case .operationFailed(let message) = error as? RuntimeServiceControlError else {
                return XCTFail("Expected RuntimeServiceControlError")
            }
            XCTAssertTrue(message.contains("controllerRestarted"))
        }
    }

    func testCreateRedisBackupRejectsMismatchedCommand() throws {
        let gateway = GuestMaintenanceGateway(
            operation: RuntimeGuestControlServiceOperation(
                operationId: "redis-backup-1",
                service: "redis-backup",
                command: .restart,
                state: .completed,
                createdAt: "2026-07-01T00:00:00+00:00",
                updatedAt: "2026-07-01T00:00:01+00:00"
            )
        )

        XCTAssertThrowsError(
            try RuntimeGuestMaintenanceControlUseCase().createRedisBackup(gateway: gateway)
        ) { error in
            guard case .operationFailed(let message) = error as? RuntimeServiceControlError else {
                return XCTFail("Expected RuntimeServiceControlError")
            }
            XCTAssertTrue(message.contains("mismatched command"))
        }
    }

    func testRestoreRedisBackupReturnsCompletedGuestOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: redisRestoreOperation(
                result: RuntimeGuestControlOperationResult(
                    restoredArchive: "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz"
                )
            )
        )

        let operation = try RuntimeGuestMaintenanceControlUseCase()
            .restoreRedisBackup(
                archive: "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz",
                gateway: gateway
            )

        XCTAssertEqual(operation.operationId, "redis-restore-1")
        XCTAssertEqual(operation.command, .redisRestore)
        XCTAssertEqual(operation.result?.restoredArchive, "/mnt/tirosh-runtime/backups/redis/redis-20260701.tar.gz")
    }

    func testRestoreRedisBackupRejectsFailedOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: redisRestoreOperation(
                state: .failed,
                failure: RuntimeGuestControlOperationFailure(
                    kind: "redis-restore-archive-missing",
                    message: "redis restore archive is missing"
                )
            )
        )

        XCTAssertThrowsError(
            try RuntimeGuestMaintenanceControlUseCase().restoreRedisBackup(
                archive: "/mnt/tirosh-runtime/backups/redis/missing.tar.gz",
                gateway: gateway
            )
        ) { error in
            guard case .operationFailed(let message) = error as? RuntimeServiceControlError else {
                return XCTFail("Expected RuntimeServiceControlError")
            }
            XCTAssertTrue(message.contains("redis-restore-archive-missing"))
        }
    }

    func testRepairDatastoreReturnsCompletedGuestOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: datastoreRepairOperation()
        )

        let operation = try RuntimeGuestMaintenanceControlUseCase()
            .repairDatastore(gateway: gateway)

        XCTAssertEqual(operation.operationId, "datastore-repair-1")
        XCTAssertEqual(operation.service, "datastore-repair")
        XCTAssertEqual(operation.command, .repairDatastore)
    }

    func testRepairDatastoreRejectsFailedOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: datastoreRepairOperation(
                state: .failed,
                failure: RuntimeGuestControlOperationFailure(
                    kind: "datastore-repair-failed",
                    message: "redis append-only file repair failed"
                )
            )
        )

        XCTAssertThrowsError(
            try RuntimeGuestMaintenanceControlUseCase().repairDatastore(gateway: gateway)
        ) { error in
            guard case .operationFailed(let message) = error as? RuntimeServiceControlError else {
                return XCTFail("Expected RuntimeServiceControlError")
            }
            XCTAssertTrue(message.contains("datastore-repair-failed"))
        }
    }

    func testRequestDatastoreRepairPreservesFailedGuestOperation() throws {
        let failure = RuntimeGuestControlOperationFailure(
            kind: "datastore-repair-failed",
            message: "redis append-only file repair failed"
        )
        let gateway = GuestMaintenanceGateway(
            operation: datastoreRepairOperation(
                state: .failed,
                failure: failure
            )
        )

        let operation = try RuntimeGuestMaintenanceControlUseCase()
            .requestDatastoreRepair(gateway: gateway)

        XCTAssertEqual(operation.service, "datastore-repair")
        XCTAssertEqual(operation.command, .repairDatastore)
        XCTAssertEqual(operation.state, .failed)
        XCTAssertEqual(operation.failure, failure)
    }

    func testActivateUpdateReturnsCompletedGuestOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: updateActivationOperation(
                result: RuntimeGuestControlOperationResult(
                    requestId: "update-activation-request-1",
                    version: "0.2.0"
                )
            )
        )

        let operation = try RuntimeGuestMaintenanceControlUseCase()
            .activateUpdate(
                requestId: "update-activation-request-1",
                version: "0.2.0",
                gateway: gateway
            )

        XCTAssertEqual(operation.operationId, "update-activation-1")
        XCTAssertEqual(operation.service, "update-activation")
        XCTAssertEqual(operation.command, .updateActivation)
        XCTAssertEqual(operation.result?.requestId, "update-activation-request-1")
        XCTAssertEqual(operation.result?.version, "0.2.0")
    }

    func testActivateUpdateRejectsFailedOperation() throws {
        let gateway = GuestMaintenanceGateway(
            operation: updateActivationOperation(
                state: .failed,
                failure: RuntimeGuestControlOperationFailure(
                    kind: "docker-image-bundle-directory-missing",
                    message: "docker image bundle directory is missing"
                )
            )
        )

        XCTAssertThrowsError(
            try RuntimeGuestMaintenanceControlUseCase().activateUpdate(
                requestId: "update-activation-request-1",
                version: "0.2.0",
                gateway: gateway
            )
        ) { error in
            guard case .operationFailed(let message) = error as? RuntimeServiceControlError else {
                return XCTFail("Expected RuntimeServiceControlError")
            }
            XCTAssertTrue(message.contains("docker-image-bundle-directory-missing"))
        }
    }
}

private final class GuestMaintenanceGateway: RuntimeGuestControlGateway {
    private let operation: RuntimeGuestControlServiceOperation

    init(operation: RuntimeGuestControlServiceOperation) {
        self.operation = operation
    }

    func listServices() throws -> RuntimeGuestControlServiceList {
        RuntimeGuestControlServiceList(services: [])
    }

    func stackStatus() throws -> RuntimeGuestControlStackStatus {
        RuntimeGuestControlStackStatus(
            state: "loaded",
            observedAt: "2026-07-01T00:00:00+00:00",
            services: []
        )
    }

    func serviceStatus(_ service: String) throws -> RuntimeGuestControlServiceStatus {
        RuntimeGuestControlServiceStatus(
            service: service,
            state: "running",
            health: "healthy",
            observedAt: "2026-07-01T00:00:00+00:00"
        )
    }

    func startService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        redisBackupOperation(service: service, command: .start)
    }

    func stopService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        redisBackupOperation(service: service, command: .stop)
    }

    func restartService(_ service: String) throws -> RuntimeGuestControlServiceOperation {
        redisBackupOperation(service: service, command: .restart)
    }

    func reconcileServices() throws -> RuntimeGuestControlServiceOperation {
        redisBackupOperation(service: "guest-stack", command: .reconcile)
    }

    func operation(_ operationId: String) throws -> RuntimeGuestControlServiceOperation {
        redisBackupOperation(operationId: operationId)
    }

    func createRedisBackup() throws -> RuntimeGuestControlServiceOperation {
        operation
    }

    func createPostgresBackup() throws -> RuntimeGuestControlServiceOperation {
        operation
    }

    func restorePostgresBackup(
        archive: String,
        restartRuntime: Bool
    ) throws -> RuntimeGuestControlServiceOperation {
        operation
    }

    func restoreRedisBackup(archive: String) throws -> RuntimeGuestControlServiceOperation {
        operation
    }

    func repairDatastore() throws -> RuntimeGuestControlServiceOperation {
        operation
    }

    func activateUpdate(requestId _: String, version _: String) throws -> RuntimeGuestControlServiceOperation {
        operation
    }

    func latestVitalDBObservation() throws -> RuntimeGuestControlVitalDBObservationRead {
        RuntimeGuestControlVitalDBObservationRead(state: .unavailable)
    }
}

private func datastoreRepairOperation(
    operationId: String = "datastore-repair-1",
    service: String = "datastore-repair",
    command: RuntimeGuestControlServiceCommand = .repairDatastore,
    state: RuntimeGuestControlOperationState = .completed,
    failure: RuntimeGuestControlOperationFailure? = nil,
    result: RuntimeGuestControlOperationResult? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: operationId,
        service: service,
        command: command,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00",
        failure: failure,
        result: result
    )
}

private func postgresBackupOperation(
    operationId: String = "postgres-backup-1",
    service: String = "postgres-backup",
    command: RuntimeGuestControlServiceCommand = .postgresBackup,
    state: RuntimeGuestControlOperationState = .completed,
    failure: RuntimeGuestControlOperationFailure? = nil,
    result: RuntimeGuestControlOperationResult? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: operationId,
        service: service,
        command: command,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00",
        failure: failure,
        result: result
    )
}

private func postgresRestoreOperation(
    operationId: String = "postgres-restore-1",
    service: String = "postgres-restore",
    command: RuntimeGuestControlServiceCommand = .postgresRestore,
    state: RuntimeGuestControlOperationState = .completed,
    failure: RuntimeGuestControlOperationFailure? = nil,
    result: RuntimeGuestControlOperationResult? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: operationId,
        service: service,
        command: command,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00",
        failure: failure,
        result: result
    )
}

private func updateActivationOperation(
    operationId: String = "update-activation-1",
    service: String = "update-activation",
    command: RuntimeGuestControlServiceCommand = .updateActivation,
    state: RuntimeGuestControlOperationState = .completed,
    failure: RuntimeGuestControlOperationFailure? = nil,
    result: RuntimeGuestControlOperationResult? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: operationId,
        service: service,
        command: command,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00",
        failure: failure,
        result: result
    )
}

private func redisRestoreOperation(
    operationId: String = "redis-restore-1",
    service: String = "redis-restore",
    command: RuntimeGuestControlServiceCommand = .redisRestore,
    state: RuntimeGuestControlOperationState = .completed,
    failure: RuntimeGuestControlOperationFailure? = nil,
    result: RuntimeGuestControlOperationResult? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: operationId,
        service: service,
        command: command,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00",
        failure: failure,
        result: result
    )
}

private func redisBackupOperation(
    operationId: String = "redis-backup-1",
    service: String = "redis-backup",
    command: RuntimeGuestControlServiceCommand = .redisBackup,
    state: RuntimeGuestControlOperationState = .completed,
    failure: RuntimeGuestControlOperationFailure? = nil,
    result: RuntimeGuestControlOperationResult? = nil
) -> RuntimeGuestControlServiceOperation {
    RuntimeGuestControlServiceOperation(
        operationId: operationId,
        service: service,
        command: command,
        state: state,
        createdAt: "2026-07-01T00:00:00+00:00",
        updatedAt: "2026-07-01T00:00:01+00:00",
        failure: failure,
        result: result
    )
}
