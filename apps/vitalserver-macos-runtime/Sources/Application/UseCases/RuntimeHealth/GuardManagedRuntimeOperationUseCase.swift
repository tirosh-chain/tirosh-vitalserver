import Contracts
import Foundation

public struct GuardManagedRuntimeOperationUseCase {
    public init() {}

    public func activeOperation(
        graceSeconds: TimeInterval,
        operations: GuardManagedRuntimeOperationOperations
    ) -> RuntimeOperation? {
        let watchdog = WatchdogRuntimeUseCase()

        if let activeLeaseOperation = operation(
            from: watchdog.operationLeaseGuardPlan(
                loadResult: operations.loadOperationLease(),
                now: operations.now()
            ),
            log: operations.log
        ) {
            return activeLeaseOperation
        }

        if let activeStatusOperation = operation(
            from: watchdog.statusManagedOperationGuardPlan(
                loadResult: operations.loadStatus(),
                now: operations.now(),
                graceSeconds: graceSeconds
            ),
            log: operations.log
        ) {
            return activeStatusOperation
        }

        guard let bootstrap = operations.activeGuestBootstrap() else {
            return nil
        }
        return operation(
            from: watchdog.guestBootstrapManagedOperationGuardPlan(
                operation: bootstrap.operation,
                updatedAt: bootstrap.updatedAt,
                now: operations.now(),
                graceSeconds: graceSeconds
            ),
            log: operations.log
        )
    }

    private func operation(
        from plan: WatchdogRuntimeManagedOperationGuardPlan,
        log: (String) -> Void
    ) -> RuntimeOperation? {
        if let logMessage = plan.logMessage {
            log(logMessage)
        }
        return plan.activeOperation
    }
}

public struct RuntimeGuestBootstrapOperation {
    public let operation: RuntimeOperation
    public let updatedAt: Date?

    public init(operation: RuntimeOperation, updatedAt: Date?) {
        self.operation = operation
        self.updatedAt = updatedAt
    }
}

public struct GuardManagedRuntimeOperationOperations {
    public let loadOperationLease: () -> RuntimeOperationLeaseLoadResult
    public let loadStatus: () -> RuntimeStatusDocumentLoadResult
    public let activeGuestBootstrap: () -> RuntimeGuestBootstrapOperation?
    public let now: () -> Date
    public let log: (String) -> Void

    public init(
        loadOperationLease: @escaping () -> RuntimeOperationLeaseLoadResult,
        loadStatus: @escaping () -> RuntimeStatusDocumentLoadResult,
        activeGuestBootstrap: @escaping () -> RuntimeGuestBootstrapOperation?,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) {
        self.loadOperationLease = loadOperationLease
        self.loadStatus = loadStatus
        self.activeGuestBootstrap = activeGuestBootstrap
        self.now = now
        self.log = log
    }
}
