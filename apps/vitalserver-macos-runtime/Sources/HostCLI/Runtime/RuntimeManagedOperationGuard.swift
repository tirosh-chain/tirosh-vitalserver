import Foundation
import Core
import Contracts

struct RuntimeGuestBootstrapOperation {
    let operation: RuntimeOperation
    let modifiedAt: Date
}

struct RuntimeManagedOperationGuard {
    private static let protectedOperations: [RuntimeOperation] = [
        .install,
        .applyBundle,
        .activateGuestUpdate,
        .rollback,
        .redisBackup,
        .repairDatastore,
        .startServices,
        .stopServices,
        .uninstall,
    ]

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
        guard Self.protectedOperations.contains(status.operation) else {
            return nil
        }
        guard let updatedAt = ISO8601DateFormatter().date(from: status.updatedAt) else {
            return status.operation
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
        let age = now().timeIntervalSince(bootstrap.modifiedAt)
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
