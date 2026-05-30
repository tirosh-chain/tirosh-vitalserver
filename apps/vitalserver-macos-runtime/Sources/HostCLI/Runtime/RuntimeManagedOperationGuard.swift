import Foundation
import Core
import Contracts

struct RuntimeGuestBootstrapOperation {
    let operation: RuntimeOperation
    let updatedAt: Date?
}

struct RuntimeManagedOperationGuard {
    private let statusReporter: RuntimeStatusReporter
    private let activeGuestBootstrap: () -> RuntimeGuestBootstrapOperation?
    private let now: () -> Date
    private let graceSeconds: TimeInterval
    private let log: (String) -> Void

    init(
        statusReporter: RuntimeStatusReporter,
        activeGuestBootstrap: @escaping () -> RuntimeGuestBootstrapOperation? = { nil },
        now: @escaping () -> Date,
        graceSeconds: TimeInterval,
        log: @escaping (String) -> Void
    ) {
        self.statusReporter = statusReporter
        self.activeGuestBootstrap = activeGuestBootstrap
        self.now = now
        self.graceSeconds = graceSeconds
        self.log = log
    }

    func activeOperation() -> RuntimeOperation? {
        if let activeStatusOperation = activeStatusOperation() {
            return activeStatusOperation
        }
        return activeBootstrapOperation()
    }

    private func activeStatusOperation() -> RuntimeOperation? {
        guard let status = statusReporter.loadStatus() else {
            return nil
        }
        guard status.status == .installing || status.status == .updating || status.status == .recovering else {
            return nil
        }
        guard RuntimeManagedOperationPolicy.isProtectedFromWatchdogRecovery(status.operation) else {
            return nil
        }
        guard let updatedAt = ISO8601DateFormatter().date(from: status.updatedAt) else {
            log("watchdog active operation guard ignored invalid updatedAt operation=\(status.operation.rawValue) updatedAt=\(status.updatedAt)")
            return nil
        }
        let age = now().timeIntervalSince(updatedAt)
        if age > graceSeconds {
            log("watchdog active operation guard expired operation=\(status.operation.rawValue) ageSeconds=\(String(format: "%.0f", age))")
            return nil
        }
        return status.operation
    }

    private func activeBootstrapOperation() -> RuntimeOperation? {
        guard let bootstrap = activeGuestBootstrap() else {
            return nil
        }
        guard let updatedAt = bootstrap.updatedAt else {
            log("watchdog guest bootstrap guard active without updatedAt operation=\(bootstrap.operation.rawValue)")
            return bootstrap.operation
        }
        let age = now().timeIntervalSince(updatedAt)
        if age > graceSeconds {
            log(
                "watchdog guest bootstrap guard expired operation=\(bootstrap.operation.rawValue) "
                    + "ageSeconds=\(String(format: "%.0f", age))"
            )
            return nil
        }
        return bootstrap.operation
    }
}
