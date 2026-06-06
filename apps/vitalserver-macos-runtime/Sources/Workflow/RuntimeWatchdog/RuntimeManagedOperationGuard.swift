import Application
import Contracts
import Foundation
import Errors

public struct RuntimeGuestBootstrapOperation {
    public let operation: RuntimeOperation
    public let updatedAt: Date?

    public init(operation: RuntimeOperation, updatedAt: Date?) {
        self.operation = operation
        self.updatedAt = updatedAt
    }
}

public struct RuntimeManagedOperationGuard {
    private let loadStatus: () -> RuntimeStatusDocumentLoadResult
    private let activeGuestBootstrap: () -> RuntimeGuestBootstrapOperation?
    private let now: () -> Date
    private let graceSeconds: TimeInterval
    private let log: (String) -> Void
    private var useCase: WatchdogRuntimeUseCase {
        WatchdogRuntimeUseCase()
    }

    public init(
        loadStatus: @escaping () -> RuntimeStatusDocumentLoadResult,
        activeGuestBootstrap: @escaping () -> RuntimeGuestBootstrapOperation? = { nil },
        now: @escaping () -> Date,
        graceSeconds: TimeInterval,
        log: @escaping (String) -> Void
    ) {
        self.loadStatus = loadStatus
        self.activeGuestBootstrap = activeGuestBootstrap
        self.now = now
        self.graceSeconds = graceSeconds
        self.log = log
    }

    public func activeOperation() -> RuntimeOperation? {
        if let activeStatusOperation = activeStatusOperation() {
            return activeStatusOperation
        }
        return activeBootstrapOperation()
    }

    private func activeStatusOperation() -> RuntimeOperation? {
        switch loadStatus() {
        case .loaded(let document):
            return operation(from: useCase.statusManagedOperationGuardPlan(
                status: document,
                now: now(),
                graceSeconds: graceSeconds
            ))
        case .missing:
            return nil
        case .failed(let message):
            return operation(from: useCase.statusReadFailureGuardPlan(reason: message))
        }
    }

    private func activeBootstrapOperation() -> RuntimeOperation? {
        guard let bootstrap = activeGuestBootstrap() else {
            return nil
        }
        return operation(from: useCase.guestBootstrapManagedOperationGuardPlan(
            operation: bootstrap.operation,
            updatedAt: bootstrap.updatedAt,
            now: now(),
            graceSeconds: graceSeconds
        ))
    }

    private func operation(from plan: WatchdogRuntimeManagedOperationGuardPlan) -> RuntimeOperation? {
        if let logMessage = plan.logMessage {
            log(logMessage)
        }
        return plan.activeOperation
    }
}
