import Application
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeGuestShutdownWorkflowContext: Equatable, Sendable {
    public let waitTimeoutSeconds: Double
    public let progressStatus: RuntimeStatusLevel
    public let progressOperation: RuntimeOperation

    public init(
        guestRunDirectory _: URL,
        waitTimeoutSeconds: Double,
        progressStatus: RuntimeStatusLevel = .updating,
        progressOperation: RuntimeOperation = .applyBundle
    ) {
        self.waitTimeoutSeconds = waitTimeoutSeconds
        self.progressStatus = progressStatus
        self.progressOperation = progressOperation
    }
}

public struct RuntimeGuestShutdownWorkflowActions {
    public let requireCapability: () throws -> Void
    public let prepareUpdateShutdown: (String, String) throws -> RuntimeGuestControlServiceOperation
    public let loadOperation: (String) throws -> RuntimeGuestControlServiceOperation
    public let requestGuestPoweroff: () throws -> RuntimeGuestControlServiceOperation
    public let writeProgressStatus: (RuntimeStatusLevel, RuntimeOperation, String) -> Void
    public let requestID: () -> String
    public let sleep: () -> Void
    public let log: (String) -> Void

    public init(
        requireCapability: @escaping () throws -> Void,
        prepareUpdateShutdown: @escaping (String, String) throws -> RuntimeGuestControlServiceOperation,
        loadOperation: @escaping (String) throws -> RuntimeGuestControlServiceOperation,
        requestGuestPoweroff: @escaping () throws -> RuntimeGuestControlServiceOperation,
        writeProgressStatus: @escaping (RuntimeStatusLevel, RuntimeOperation, String) -> Void,
        requestID: @escaping () -> String,
        sleep: @escaping () -> Void,
        log: @escaping (String) -> Void
    ) {
        self.requireCapability = requireCapability
        self.prepareUpdateShutdown = prepareUpdateShutdown
        self.loadOperation = loadOperation
        self.requestGuestPoweroff = requestGuestPoweroff
        self.writeProgressStatus = writeProgressStatus
        self.requestID = requestID
        self.sleep = sleep
        self.log = log
    }
}

public struct RuntimeGuestShutdownWorkflow {
    private let useCase: RuntimeGuestShutdownUseCase

    public init(useCase: RuntimeGuestShutdownUseCase = RuntimeGuestShutdownUseCase()) {
        self.useCase = useCase
    }

    public func prepareForUpdate(
        manifest: UpdateBundleManifest,
        context: RuntimeGuestShutdownWorkflowContext,
        actions: RuntimeGuestShutdownWorkflowActions
    ) throws {
        try prepareForUpdate(version: manifest.version, context: context, actions: actions)
    }

    public func prepareForUpdate(
        version: String,
        context: RuntimeGuestShutdownWorkflowContext,
        actions: RuntimeGuestShutdownWorkflowActions
    ) throws {
        switch useCase.executionPlan(version: version) {
        case .prepare(let version, let requestLog, let readyLog):
            actions.log(requestLog)
            try actions.requireCapability()
            let operation = try actions.prepareUpdateShutdown(
                actions.requestID(),
                version
            )
            try waitForShutdownReady(operation, context: context, actions: actions)
            let poweroff = try actions.requestGuestPoweroff()
            actions.log("guest poweroff requested operationId=\(poweroff.operationId)")
            actions.log(readyLog)
        }
    }

    private func waitForShutdownReady(
        _ operation: RuntimeGuestControlServiceOperation,
        context: RuntimeGuestShutdownWorkflowContext,
        actions: RuntimeGuestShutdownWorkflowActions
    ) throws {
        actions.log(useCase.waitStartedLogMessage(
            timeoutSeconds: context.waitTimeoutSeconds
        ))
        let configuration = try useCase.operationWaitConfiguration(
            timeoutSeconds: context.waitTimeoutSeconds
        )
        var current = operation
        for attempt in 0..<configuration.maxAttempts {
            switch current.state {
            case .completed:
                try validatePoweroffReady(current)
                actions.log("guest update shutdown operation completed operationId=\(current.operationId)")
                return
            case .failed:
                throw RuntimeGuestUpdateUseCaseError.operationFailed(
                    operationFailureMessage(current)
                )
            case .accepted, .running:
                let message = "guest update shutdown operation \(current.state.rawValue)"
                let shouldPublishProgress = attempt % configuration.progressEveryAttempts == 0
                if shouldPublishProgress {
                    actions.log(message)
                    actions.writeProgressStatus(context.progressStatus, context.progressOperation, message)
                }
                if attempt < configuration.maxAttempts - 1 {
                    actions.sleep()
                    current = try actions.loadOperation(operation.operationId)
                }
            case .cancelled, .interrupted:
                throw RuntimeGuestUpdateUseCaseError.operationFailed(
                    "guest update shutdown operation \(current.state.rawValue) "
                        + "operationId=\(current.operationId)"
                )
            }
        }

        throw RuntimeGuestUpdateUseCaseError.operationFailed("guest update shutdown timed out")
    }

    private func validatePoweroffReady(
        _ operation: RuntimeGuestControlServiceOperation
    ) throws {
        guard operation.result?.shutdownPhase == "poweroff-ready" else {
            throw RuntimeGuestUpdateUseCaseError.operationFailed(
                "guest update shutdown completed without poweroff-ready operationId=\(operation.operationId)"
            )
        }
        guard let redisBackupPath = operation.result?.redisBackupPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !redisBackupPath.isEmpty else {
            throw RuntimeGuestUpdateUseCaseError.operationFailed(
                "guest update shutdown completed without Redis backup receipt operationId=\(operation.operationId)"
            )
        }
        guard let postgresBackupPath = operation.result?.postgresBackupPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !postgresBackupPath.isEmpty else {
            throw RuntimeGuestUpdateUseCaseError.operationFailed(
                "guest update shutdown completed without PostgreSQL backup receipt operationId=\(operation.operationId)"
            )
        }
    }

    private func operationFailureMessage(
        _ operation: RuntimeGuestControlServiceOperation
    ) -> String {
        guard let failure = operation.failure else {
            return "guest update shutdown failed operationId=\(operation.operationId)"
        }
        return "guest update shutdown failed operationId=\(operation.operationId) kind=\(failure.kind) reason=\(failure.message)"
    }
}
