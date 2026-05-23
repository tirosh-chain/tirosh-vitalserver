import Foundation
import Core
import Contracts

struct RuntimeManagedOperationGuard {
    private let statusReporter: RuntimeStatusReporter
    private let now: () -> Date
    private let graceSeconds: TimeInterval
    private let log: (String) -> Void

    init(
        statusReporter: RuntimeStatusReporter,
        now: @escaping () -> Date,
        graceSeconds: TimeInterval,
        log: @escaping (String) -> Void
    ) {
        self.statusReporter = statusReporter
        self.now = now
        self.graceSeconds = graceSeconds
        self.log = log
    }

    func activeOperation() -> RuntimeOperation? {
        guard let status = statusReporter.loadStatus() else {
            return nil
        }
        guard status.status == .updating || status.status == .recovering else {
            return nil
        }
        guard [.applyBundle, .activateGuestUpdate, .rollback].contains(status.operation) else {
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
}
