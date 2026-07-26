import Contracts
import Foundation

public struct GuardManagedRuntimeOperationUseCase {
    public init() {}

    public func activeOperation(operations: GuardManagedRuntimeOperationOperations) -> RuntimeOperation? {
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

        return nil
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

public struct GuardManagedRuntimeOperationOperations {
    public let loadOperationLease: () -> RuntimeOperationLeaseLoadResult
    public let now: () -> Date
    public let log: (String) -> Void

    public init(
        loadOperationLease: @escaping () -> RuntimeOperationLeaseLoadResult,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) {
        self.loadOperationLease = loadOperationLease
        self.now = now
        self.log = log
    }
}
