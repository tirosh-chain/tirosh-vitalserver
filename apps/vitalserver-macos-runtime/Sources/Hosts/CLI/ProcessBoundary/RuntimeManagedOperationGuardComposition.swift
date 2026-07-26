import Application
import Contracts
import Foundation

public struct RuntimeManagedOperationGuardComposition {
    private let operations: GuardManagedRuntimeOperationOperations

    public init(
        operations: GuardManagedRuntimeOperationOperations
    ) {
        self.operations = operations
    }

    public static func make(
        operationLeaseReader: RuntimeOperationLeaseReading,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) -> RuntimeManagedOperationGuardComposition {
        RuntimeManagedOperationGuardComposition(
            operations: GuardManagedRuntimeOperationOperations(
                loadOperationLease: operationLeaseReader.loadOperationLease,
                now: now,
                log: log
            )
        )
    }

    public func activeOperation() -> RuntimeOperation? {
        GuardManagedRuntimeOperationUseCase().activeOperation(operations: operations)
    }
}
