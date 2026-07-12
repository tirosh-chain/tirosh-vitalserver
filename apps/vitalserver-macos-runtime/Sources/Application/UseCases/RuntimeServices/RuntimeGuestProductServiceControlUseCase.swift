import Contracts
import Errors

public struct RuntimeGuestProductServiceControlUseCase {
    public init() {}

    public func startService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        try runServiceCommand(
            service,
            command: .start,
            action: { try gateway.startService(service) }
        )
    }

    public func stopService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        try runServiceCommand(
            service,
            command: .stop,
            action: { try gateway.stopService(service) }
        )
    }

    public func restartService(
        _ service: String,
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        try runServiceCommand(
            service,
            command: .restart,
            action: { try gateway.restartService(service) }
        )
    }

    public func reconcileServices(
        gateway: RuntimeGuestControlGateway
    ) throws -> RuntimeGuestControlServiceOperation {
        try runServiceCommand(
            "guest-stack",
            command: .reconcile,
            action: { try gateway.reconcileServices() }
        )
    }

    private func runServiceCommand(
        _ service: String,
        command: RuntimeGuestControlServiceCommand,
        action: () throws -> RuntimeGuestControlServiceOperation
    ) throws -> RuntimeGuestControlServiceOperation {
        let operation = try action()
        guard operation.service == service else {
            throw RuntimeServiceControlError.operationFailed(
                "guest service \(command.rawValue) returned mismatched service expected=\(service) actual=\(operation.service)"
            )
        }
        guard operation.command == command else {
            throw RuntimeServiceControlError.operationFailed(
                "guest service \(command.rawValue) returned mismatched command service=\(service) command=\(operation.command.rawValue)"
            )
        }
        if operation.state == .failed || operation.state == .cancelled || operation.state == .interrupted {
            throw RuntimeServiceControlError.operationFailed(failureMessage(operation))
        }
        return operation
    }

    private func failureMessage(_ operation: RuntimeGuestControlServiceOperation) -> String {
        guard let failure = operation.failure else {
            return "guest service operation did not complete service=\(operation.service) operationId=\(operation.operationId) state=\(operation.state.rawValue)"
        }
        var message = "guest service operation did not complete service=\(operation.service)"
        message += " operationId=\(operation.operationId)"
        message += " state=\(operation.state.rawValue)"
        message += " kind=\(failure.kind)"
        message += " reason=\(failure.message)"
        if let evidencePath = failure.evidencePath, !evidencePath.isEmpty {
            message += " evidencePath=\(evidencePath)"
        }
        return message
    }
}

extension RuntimeGuestProductServiceControlUseCase: RuntimeGuestProductServiceCommandControlling {}
