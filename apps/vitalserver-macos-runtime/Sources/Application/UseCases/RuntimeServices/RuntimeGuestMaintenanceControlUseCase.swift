import Contracts
import Errors

public struct RuntimeGuestMaintenanceControlUseCase {
    public init() {}

    public func createRedisBackup(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        let operation = try gateway.createRedisBackup()
        return try validateOperation(
            operation,
            expectedService: "redis-backup",
            expectedCommand: .redisBackup,
            operationName: "guest redis backup"
        )
    }

    public func restoreRedisBackup(
        archive: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        let operation = try gateway.restoreRedisBackup(archive: archive)
        return try validateOperation(
            operation,
            expectedService: "redis-restore",
            expectedCommand: .redisRestore,
            operationName: "guest redis restore"
        )
    }

    public func repairDatastore(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        let operation = try gateway.repairDatastore()
        return try validateOperation(
            operation,
            expectedService: "datastore-repair",
            expectedCommand: .repairDatastore,
            operationName: "guest datastore repair"
        )
    }

    public func activateUpdate(
        requestId: String,
        version: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        let operation = try gateway.activateUpdate(
            requestId: requestId,
            version: version
        )
        return try validateOperation(
            operation,
            expectedService: "update-activation",
            expectedCommand: .updateActivation,
            operationName: "guest update activation"
        )
    }

    public func prepareUpdateShutdown(
        requestId: String,
        version: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        let operation = try gateway.prepareUpdateShutdown(
            requestId: requestId,
            version: version
        )
        return try validateOperation(
            operation,
            expectedService: "update-shutdown",
            expectedCommand: .updateShutdown,
            operationName: "guest update shutdown"
        )
    }

    public func requestGuestPoweroff(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        let operation = try gateway.requestGuestPoweroff()
        return try validateOperation(
            operation,
            expectedService: "guest-poweroff",
            expectedCommand: .requestGuestPoweroff,
            operationName: "guest poweroff request"
        )
    }

    private func validateOperation(
        _ operation: RuntimeGuestControlServiceOperation,
        expectedService: String,
        expectedCommand: RuntimeGuestControlServiceCommand,
        operationName: String
    ) throws -> RuntimeGuestControlServiceOperation {
        guard operation.service == expectedService else {
            throw RuntimeServiceControlError.operationFailed(
                "\(operationName) returned mismatched service expected=\(expectedService) actual=\(operation.service)"
            )
        }
        guard operation.command == expectedCommand else {
            throw RuntimeServiceControlError.operationFailed(
                "\(operationName) returned mismatched command command=\(operation.command.rawValue)"
            )
        }
        if operation.state == .failed {
            throw RuntimeServiceControlError.operationFailed(
                failureMessage(operation, operationName: operationName)
            )
        }
        return operation
    }

    private func failureMessage(
        _ operation: RuntimeGuestControlServiceOperation,
        operationName: String
    ) -> String {
        guard let failure = operation.failure else {
            return "\(operationName) failed operationId=\(operation.operationId)"
        }
        var message = "\(operationName) failed operationId=\(operation.operationId)"
        message += " kind=\(failure.kind)"
        message += " reason=\(failure.message)"
        if let evidencePath = failure.evidencePath, !evidencePath.isEmpty {
            message += " evidencePath=\(evidencePath)"
        }
        return message
    }
}

extension RuntimeGuestMaintenanceControlUseCase: RuntimeGuestMaintenanceCommandControlling {}
