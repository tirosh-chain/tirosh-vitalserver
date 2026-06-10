import Contracts
import Domain
import Foundation

public struct WatchdogRuntimeSkipPlan: Equatable, Sendable {
    public let logMessage: String
    public let lifecycleMessage: String
    public let eventType: RuntimeEventType
    public let printMessage: String

    public init(
        logMessage: String,
        lifecycleMessage: String,
        eventType: RuntimeEventType,
        printMessage: String
    ) {
        self.logMessage = logMessage
        self.lifecycleMessage = lifecycleMessage
        self.eventType = eventType
        self.printMessage = printMessage
    }
}

public struct WatchdogRuntimeHealthPassPlan: Equatable, Sendable {
    public let statusMessage: String
    public let printMessage: String

    public init(statusMessage: String, printMessage: String) {
        self.statusMessage = statusMessage
        self.printMessage = printMessage
    }
}

public struct WatchdogRuntimeObservedStatusPlan: Equatable, Sendable {
    public let status: RuntimeStatusLevel
    public let message: String
    public let eventType: RuntimeEventType
    public let printMessage: String
    public let logMessage: String?

    public init(
        status: RuntimeStatusLevel,
        message: String,
        eventType: RuntimeEventType,
        printMessage: String,
        logMessage: String?
    ) {
        self.status = status
        self.message = message
        self.eventType = eventType
        self.printMessage = printMessage
        self.logMessage = logMessage
    }
}

public struct WatchdogRuntimeTerminalRecoveryPlan: Equatable, Sendable {
    public let detectedLogMessage: String
    public let startedStatusMessage: String
    public let finalStatus: RuntimeStatusLevel
    public let finalStatusMessage: String
    public let printMessage: String

    public init(
        detectedLogMessage: String,
        startedStatusMessage: String,
        finalStatus: RuntimeStatusLevel,
        finalStatusMessage: String,
        printMessage: String
    ) {
        self.detectedLogMessage = detectedLogMessage
        self.startedStatusMessage = startedStatusMessage
        self.finalStatus = finalStatus
        self.finalStatusMessage = finalStatusMessage
        self.printMessage = printMessage
    }
}

public struct WatchdogRuntimeRecoveryExecutionPlan: Equatable, Sendable {
    public let reason: String
    public let recoveryPlan: RuntimeRecoveryPlan
    public let detectedLogMessage: String
    public let startedStatusMessage: String
    public let planLogMessage: String
    public let plannedEventMessage: String
    public let vmRestartEventMessage: String?
    public let proxyRestartEventMessage: String?

    public init(
        reason: String,
        recoveryPlan: RuntimeRecoveryPlan,
        detectedLogMessage: String,
        startedStatusMessage: String,
        planLogMessage: String,
        plannedEventMessage: String,
        vmRestartEventMessage: String?,
        proxyRestartEventMessage: String?
    ) {
        self.reason = reason
        self.recoveryPlan = recoveryPlan
        self.detectedLogMessage = detectedLogMessage
        self.startedStatusMessage = startedStatusMessage
        self.planLogMessage = planLogMessage
        self.plannedEventMessage = plannedEventMessage
        self.vmRestartEventMessage = vmRestartEventMessage
        self.proxyRestartEventMessage = proxyRestartEventMessage
    }
}

public struct WatchdogRuntimeCommandFailurePlan: Equatable, Sendable {
    public let status: RuntimeStatusLevel
    public let message: String
    public let eventType: RuntimeEventType
    public let printMessage: String

    public init(
        status: RuntimeStatusLevel,
        message: String,
        eventType: RuntimeEventType,
        printMessage: String
    ) {
        self.status = status
        self.message = message
        self.eventType = eventType
        self.printMessage = printMessage
    }
}

public struct WatchdogRuntimeRecoveryCompletionPlan: Equatable, Sendable {
    public let status: RuntimeStatusLevel
    public let message: String
    public let printMessage: String

    public init(status: RuntimeStatusLevel, message: String, printMessage: String) {
        self.status = status
        self.message = message
        self.printMessage = printMessage
    }
}

public struct WatchdogRuntimeLifecycleMarkPlan: Equatable, Sendable {
    public let lifecycle: RuntimeVMLifecycleDocument?
    public let eventMessage: String

    public init(lifecycle: RuntimeVMLifecycleDocument?, eventMessage: String) {
        self.lifecycle = lifecycle
        self.eventMessage = eventMessage
    }
}

public struct WatchdogRuntimeManagedOperationGuardPlan: Equatable, Sendable {
    public let activeOperation: RuntimeOperation?
    public let logMessage: String?

    public init(activeOperation: RuntimeOperation?, logMessage: String?) {
        self.activeOperation = activeOperation
        self.logMessage = logMessage
    }
}

public enum WatchdogRuntimeInitialSnapshotDecision: Equatable, Sendable {
    case healthy(WatchdogRuntimeHealthPassPlan)
    case recoverySuppressed(WatchdogRuntimeObservedStatusPlan)
    case recoveryDeferred(WatchdogRuntimeObservedStatusPlan)
    case needsRecoveryProbe
}

public enum WatchdogRuntimeRecoveryDecision: Equatable, Sendable {
    case healthy(WatchdogRuntimeHealthPassPlan)
    case recoveryDisabled(WatchdogRuntimeTerminalRecoveryPlan)
    case recoveryDeferred(WatchdogRuntimeObservedStatusPlan)
    case recoverySuppressed(WatchdogRuntimeObservedStatusPlan)
    case unrecoverable(WatchdogRuntimeTerminalRecoveryPlan)
    case recover(WatchdogRuntimeRecoveryExecutionPlan)
}

public struct WatchdogRuntimeUseCase {
    public init() {}

    public func activeOperationSkipPlan(_ activeOperation: RuntimeOperation) -> WatchdogRuntimeSkipPlan {
        let message = "watchdog skipped during active runtime operation operation=\(activeOperation.rawValue)"
        return WatchdogRuntimeSkipPlan(
            logMessage: message,
            lifecycleMessage: message,
            eventType: .watchdogSkipped,
            printMessage: "watchdog: skipped active operation"
        )
    }

    public func statusReadFailureGuardPlan(reason: String) -> WatchdogRuntimeManagedOperationGuardPlan {
        WatchdogRuntimeManagedOperationGuardPlan(
            activeOperation: nil,
            logMessage: "watchdog active operation guard ignored status read failure error=\(reason)"
        )
    }

    public func operationLeaseGuardPlan(
        loadResult: RuntimeOperationLeaseLoadResult,
        now: Date
    ) -> WatchdogRuntimeManagedOperationGuardPlan {
        switch loadResult {
        case .missing:
            return WatchdogRuntimeManagedOperationGuardPlan(activeOperation: nil, logMessage: nil)
        case .loaded(let document):
            return operationLeaseGuardPlan(lease: document, now: now)
        case .failed(let message):
            return WatchdogRuntimeManagedOperationGuardPlan(
                activeOperation: .unknown("operation-lease-read-failed"),
                logMessage: "watchdog operation lease guard blocked on lease read failure error=\(message)"
            )
        }
    }

    public func operationLeaseGuardPlan(
        lease: RuntimeOperationLeaseDocument,
        now: Date
    ) -> WatchdogRuntimeManagedOperationGuardPlan {
        guard let expiresAt = lease.expiresAt else {
            return WatchdogRuntimeManagedOperationGuardPlan(
                activeOperation: lease.operation,
                logMessage: "watchdog operation lease guard active without expiresAt operation=\(lease.operation.rawValue) operationId=\(lease.operationId)"
            )
        }
        guard let expirationDate = ISO8601DateFormatter().date(from: expiresAt) else {
            return WatchdogRuntimeManagedOperationGuardPlan(
                activeOperation: lease.operation,
                logMessage: "watchdog operation lease guard active with invalid expiresAt operation=\(lease.operation.rawValue) operationId=\(lease.operationId) expiresAt=\(expiresAt)"
            )
        }
        if now > expirationDate {
            let age = now.timeIntervalSince(expirationDate)
            return WatchdogRuntimeManagedOperationGuardPlan(
                activeOperation: nil,
                logMessage: "watchdog operation lease guard expired operation=\(lease.operation.rawValue) operationId=\(lease.operationId) expiredSeconds=\(formatAgeSeconds(age))"
            )
        }
        return WatchdogRuntimeManagedOperationGuardPlan(activeOperation: lease.operation, logMessage: nil)
    }

    public func statusManagedOperationGuardPlan(
        loadResult: RuntimeStatusDocumentLoadResult,
        now: Date,
        graceSeconds: TimeInterval
    ) -> WatchdogRuntimeManagedOperationGuardPlan {
        switch loadResult {
        case .loaded(let document):
            return statusManagedOperationGuardPlan(
                status: document,
                now: now,
                graceSeconds: graceSeconds
            )
        case .missing:
            return WatchdogRuntimeManagedOperationGuardPlan(activeOperation: nil, logMessage: nil)
        case .failed(let message):
            return statusReadFailureGuardPlan(reason: message)
        }
    }

    public func statusManagedOperationGuardPlan(
        status: RuntimeStatusDocument,
        now: Date,
        graceSeconds: TimeInterval
    ) -> WatchdogRuntimeManagedOperationGuardPlan {
        guard status.status == .installing ||
            status.status == .updating ||
            status.status == .recovering else {
            return WatchdogRuntimeManagedOperationGuardPlan(activeOperation: nil, logMessage: nil)
        }
        guard RuntimeManagedOperationPolicy.isProtectedFromWatchdogRecovery(status.operation) else {
            return WatchdogRuntimeManagedOperationGuardPlan(activeOperation: nil, logMessage: nil)
        }
        guard let updatedAt = ISO8601DateFormatter().date(from: status.updatedAt) else {
            return WatchdogRuntimeManagedOperationGuardPlan(
                activeOperation: nil,
                logMessage: "watchdog active operation guard ignored invalid updatedAt operation=\(status.operation.rawValue) updatedAt=\(status.updatedAt)"
            )
        }
        let age = now.timeIntervalSince(updatedAt)
        if age > graceSeconds {
            return WatchdogRuntimeManagedOperationGuardPlan(
                activeOperation: nil,
                logMessage: "watchdog active operation guard expired operation=\(status.operation.rawValue) ageSeconds=\(formatAgeSeconds(age))"
            )
        }
        return WatchdogRuntimeManagedOperationGuardPlan(activeOperation: status.operation, logMessage: nil)
    }

    public func guestBootstrapManagedOperationGuardPlan(
        operation: RuntimeOperation,
        updatedAt: Date?,
        now: Date,
        graceSeconds: TimeInterval
    ) -> WatchdogRuntimeManagedOperationGuardPlan {
        guard let updatedAt else {
            return WatchdogRuntimeManagedOperationGuardPlan(
                activeOperation: operation,
                logMessage: "watchdog guest bootstrap guard active without updatedAt operation=\(operation.rawValue)"
            )
        }
        let age = now.timeIntervalSince(updatedAt)
        if age > graceSeconds {
            return WatchdogRuntimeManagedOperationGuardPlan(
                activeOperation: nil,
                logMessage: "watchdog guest bootstrap guard expired operation=\(operation.rawValue) ageSeconds=\(formatAgeSeconds(age))"
            )
        }
        return WatchdogRuntimeManagedOperationGuardPlan(activeOperation: operation, logMessage: nil)
    }

    public func initialSnapshotDecision(_ snapshot: RuntimeHealthSnapshot) -> WatchdogRuntimeInitialSnapshotDecision {
        if RuntimeHealthSnapshotPolicy.isHealthy(snapshot) {
            return .healthy(healthPassPlan())
        }
        if let reason = RuntimeWatchdogRecoveryPolicy.automaticRecoverySuppressionReason(snapshot) {
            return .recoverySuppressed(suppressedPlan(reason: reason))
        }
        if let reason = RuntimeWatchdogRecoveryPolicy.automaticRecoveryDeferralReason(snapshot) {
            return .recoveryDeferred(deferredPlan(reason: reason))
        }
        return .needsRecoveryProbe
    }

    public func recoveryDecision(
        snapshot: RuntimeHealthSnapshot,
        hostProxyLivenessHTTP: String,
        automaticRecoveryEnabled: Bool
    ) -> WatchdogRuntimeRecoveryDecision {
        switch RuntimeWatchdogRecoveryPolicy.decision(
            snapshot: snapshot,
            hostProxyLivenessHTTP: hostProxyLivenessHTTP,
            automaticRecoveryEnabled: automaticRecoveryEnabled
        ) {
        case .healthy:
            return .healthy(healthPassPlan())
        case .recoveryDisabled(let reason):
            return .recoveryDisabled(terminalPlan(
                reason: reason,
                finalStatus: .degraded,
                finalStatusMessage: "watchdog detected unhealthy runtime; automatic recovery is disabled: \(reason)",
                printMessage: "watchdog: recovery disabled"
            ))
        case .recoveryDeferred(let reason):
            return .recoveryDeferred(deferredPlan(reason: reason))
        case .recoverySuppressed(let reason):
            return .recoverySuppressed(suppressedPlan(reason: reason))
        case .unrecoverable(let reason):
            return .unrecoverable(terminalPlan(
                reason: reason,
                finalStatus: .critical,
                finalStatusMessage: "watchdog cannot recover missing installed artifacts: \(reason)",
                printMessage: "watchdog: critical"
            ))
        case .recover(let reason, let plan):
            return .recover(recoveryExecutionPlan(
                reason: reason,
                recoveryPlan: plan,
                hostProxyLivenessHTTP: hostProxyLivenessHTTP,
                snapshot: snapshot
            ))
        }
    }

    public func lifecycleMarkPlan(_ snapshot: RuntimeHealthSnapshot) -> WatchdogRuntimeLifecycleMarkPlan {
        guard let lifecycle = snapshot.vmLifecycle,
              lifecycle.state == .starting || lifecycle.state == .bootstrapping
        else {
            return WatchdogRuntimeLifecycleMarkPlan(lifecycle: nil, eventMessage: "")
        }
        return WatchdogRuntimeLifecycleMarkPlan(
            lifecycle: lifecycle,
            eventMessage: "VM lifecycle marked running after healthy runtime observation"
        )
    }

    public func lifecycleMarkFailedLogMessage(error: Error) -> String {
        "watchdog failed to mark VM lifecycle running error=\(error.localizedDescription)"
    }

    public func commandFailurePlan(service: RuntimeManagedService, error: Error) -> WatchdogRuntimeCommandFailurePlan {
        let serviceName = restartServiceName(service)
        return WatchdogRuntimeCommandFailurePlan(
            status: .critical,
            message: "watchdog \(serviceName) restart failed: \(error.localizedDescription)",
            eventType: .runtimeCommandFailed,
            printMessage: "watchdog: critical"
        )
    }

    public func recoveryCompletionPlan(_ snapshot: RuntimeHealthSnapshot) -> WatchdogRuntimeRecoveryCompletionPlan {
        guard RuntimeHealthSnapshotPolicy.isHealthy(snapshot) else {
            return WatchdogRuntimeRecoveryCompletionPlan(
                status: .critical,
                message: "watchdog recovery failed: \(RuntimeFailureReasonText.describe(snapshot.failureReasons))",
                printMessage: "watchdog: critical"
            )
        }
        return WatchdogRuntimeRecoveryCompletionPlan(
            status: .healthy,
            message: "watchdog recovery completed",
            printMessage: "watchdog: recovered"
        )
    }

    private func healthPassPlan() -> WatchdogRuntimeHealthPassPlan {
        WatchdogRuntimeHealthPassPlan(
            statusMessage: "runtime watchdog passed",
            printMessage: "watchdog: ok"
        )
    }

    private func suppressedPlan(reason: String) -> WatchdogRuntimeObservedStatusPlan {
        observedStatusPlan(
            status: .critical,
            message: "watchdog recovery suppressed: \(reason)",
            eventType: .recoverySuppressed,
            printMessage: "watchdog: suppressed"
        )
    }

    private func deferredPlan(reason: String) -> WatchdogRuntimeObservedStatusPlan {
        observedStatusPlan(
            status: .degraded,
            message: "watchdog recovery deferred: \(reason)",
            eventType: .recoveryDeferred,
            printMessage: "watchdog: deferred"
        )
    }

    private func observedStatusPlan(
        status: RuntimeStatusLevel,
        message: String,
        eventType: RuntimeEventType,
        printMessage: String
    ) -> WatchdogRuntimeObservedStatusPlan {
        WatchdogRuntimeObservedStatusPlan(
            status: status,
            message: message,
            eventType: eventType,
            printMessage: printMessage,
            logMessage: message
        )
    }

    private func terminalPlan(
        reason: String,
        finalStatus: RuntimeStatusLevel,
        finalStatusMessage: String,
        printMessage: String
    ) -> WatchdogRuntimeTerminalRecoveryPlan {
        WatchdogRuntimeTerminalRecoveryPlan(
            detectedLogMessage: "watchdog detected unhealthy runtime reasons=\(reason)",
            startedStatusMessage: "watchdog recovery started: \(reason)",
            finalStatus: finalStatus,
            finalStatusMessage: finalStatusMessage,
            printMessage: printMessage
        )
    }

    private func recoveryExecutionPlan(
        reason: String,
        recoveryPlan: RuntimeRecoveryPlan,
        hostProxyLivenessHTTP: String,
        snapshot: RuntimeHealthSnapshot
    ) -> WatchdogRuntimeRecoveryExecutionPlan {
        let restartReasons = restartReasonText(recoveryPlan)
        return WatchdogRuntimeRecoveryExecutionPlan(
            reason: reason,
            recoveryPlan: recoveryPlan,
            detectedLogMessage: "watchdog detected unhealthy runtime reasons=\(reason)",
            startedStatusMessage: "watchdog recovery started: \(reason)",
            planLogMessage: "watchdog recovery plan vm=\(recoveryPlan.restartVM) proxy=\(recoveryPlan.restartProxy) restartReasons=\(restartReasons) hostProxyHealth=\(hostProxyLivenessHTTP) hostProxyReady=\(snapshot.hostProxyHTTP) guestReady=\(snapshot.guestHTTP)",
            plannedEventMessage: "watchdog recovery planned vm=\(recoveryPlan.restartVM) proxy=\(recoveryPlan.restartProxy) reasons=\(restartReasons)",
            vmRestartEventMessage: recoveryPlan.restartVM ? "watchdog restart dispatched services=vm,guest-log-sync" : nil,
            proxyRestartEventMessage: recoveryPlan.restartProxy ? "watchdog restart dispatched services=proxy" : nil
        )
    }

    private func restartReasonText(_ recoveryPlan: RuntimeRecoveryPlan) -> String {
        let reasonCodes = recoveryPlan.restartReasonCodes
        guard !reasonCodes.isEmpty else {
            return "none"
        }
        return reasonCodes.joined(separator: ",")
    }

    private func restartServiceName(_ service: RuntimeManagedService) -> String {
        switch service {
        case .vm:
            return "VM"
        case .proxy:
            return "proxy"
        case .guestLogSync:
            return "guest-log-sync"
        case .sleepPrevention:
            return "sleep-prevention"
        case .watchdog:
            return "watchdog"
        }
    }

    private func formatAgeSeconds(_ age: TimeInterval) -> String {
        String(format: "%.0f", age)
    }
}
