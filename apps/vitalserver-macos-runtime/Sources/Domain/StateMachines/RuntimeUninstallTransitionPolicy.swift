import Contracts
import Foundation

public enum RuntimeUninstallWorkflowState: Equatable, Sendable {
    case notStarted
    case started
    case vitalServerBackupRequested
    case vitalServerBackupCompleted
    case stopServicesRequested
    case serviceStopBlocked
    case stoppedVerified
    case filesRemovalStarted
    case filesRemovalBlocked
    case cleanupVerified
    case receiptsForgetStarted
    case receiptsForgetBlocked
    case completed
    case failed
}

public enum RuntimeUninstallWorkflowEvent: Equatable, Sendable {
    case start(clean: Bool)
    case vitalFilesOwnershipUnavailable(reason: String, forceClean: Bool)
    case vitalServerBackupRequested
    case vitalServerBackupSucceeded
    case vitalServerBackupFailed(reason: String)
    case stopServicesRequested
    case stopServicesFailed(input: RuntimeUninstallReadinessInput, commandFailureReason: String)
    case stoppedStateObserved(RuntimeUninstallReadinessInput)
    case filesRemovalStarted
    case cleanupArtifactsObserved([RuntimeInstallArtifactState])
    case receiptsForgetStarted
    case receiptForgetFailed(identifier: String, reason: String)
    case packageReceiptsObserved([RuntimePackageReceiptState])
}

public enum RuntimeUninstallWorkflowCommand: Equatable, Sendable {
    case createVitalServerBackup
    case stopRuntimeServices
    case removeFiles
    case forgetPackageReceipts
    case complete
}

public struct RuntimeUninstallTransitionDecision: Equatable, Sendable {
    public let state: RuntimeUninstallWorkflowState
    public let persistedState: RuntimeUninstallState?
    public let commands: [RuntimeUninstallWorkflowCommand]
    public let blockers: [String]
    public let message: String?

    public init(
        state: RuntimeUninstallWorkflowState,
        persistedState: RuntimeUninstallState? = nil,
        commands: [RuntimeUninstallWorkflowCommand] = [],
        blockers: [String] = [],
        message: String? = nil
    ) {
        self.state = state
        self.persistedState = persistedState
        self.commands = commands
        self.blockers = blockers
        self.message = message
    }
}

public enum RuntimeUninstallTransitionPolicy {
    public static func transition(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent
    ) throws -> RuntimeUninstallTransitionDecision {
        switch (state, event) {
        case (.notStarted, .start(clean: _)):
            return RuntimeUninstallTransitionDecision(
                state: .started,
                persistedState: .started,
                message: "uninstall started"
            )

        case (.started, .vitalFilesOwnershipUnavailable(let reason, let forceClean)):
            if forceClean {
                return RuntimeUninstallTransitionDecision(
                    state: .started,
                    message: "force-clean Vital files ownership override accepted"
                )
            }
            return RuntimeUninstallTransitionDecision(
                state: .failed,
                persistedState: .failed,
                blockers: ["vital-files-ownership-unavailable:reason=\(reason)"],
                message: "Vital files ownership unavailable"
            )

        case (.started, .vitalServerBackupRequested):
            return RuntimeUninstallTransitionDecision(
                state: .vitalServerBackupRequested,
                persistedState: .vitalServerBackupRequested,
                commands: [.createVitalServerBackup],
                message: "VitalServer backup requested"
            )

        case (.vitalServerBackupRequested, .vitalServerBackupSucceeded):
            return RuntimeUninstallTransitionDecision(
                state: .vitalServerBackupCompleted,
                persistedState: .vitalServerBackupCompleted,
                message: "VitalServer backup completed"
            )

        case (.vitalServerBackupRequested, .vitalServerBackupFailed(reason: let reason)):
            return RuntimeUninstallTransitionDecision(
                state: .failed,
                persistedState: .failed,
                blockers: ["vitalserver-backup-failed:reason=\(reason)"],
                message: "VitalServer backup failed"
            )

        case (.started, .stopServicesRequested),
             (.vitalServerBackupCompleted, .stopServicesRequested):
            return RuntimeUninstallTransitionDecision(
                state: .stopServicesRequested,
                persistedState: .stopServicesRequested,
                commands: [.stopRuntimeServices],
                message: "service stop requested"
            )

        case (.stopServicesRequested, .stopServicesFailed(input: let input, commandFailureReason: let commandFailureReason)):
            let blockers = stopBlockers(input: input, commandFailureReason: commandFailureReason)
            return RuntimeUninstallTransitionDecision(
                state: .serviceStopBlocked,
                persistedState: .serviceStopBlocked,
                blockers: blockers,
                message: "service stop blocked"
            )

        case (.stopServicesRequested, .stoppedStateObserved(let input)):
            let blockers = RuntimeUninstallReadinessPolicy.blockers(input: input)
            if blockers.isEmpty {
                return RuntimeUninstallTransitionDecision(
                    state: .stoppedVerified,
                    commands: [.removeFiles]
                )
            }
            return RuntimeUninstallTransitionDecision(
                state: .serviceStopBlocked,
                persistedState: .serviceStopBlocked,
                blockers: blockers,
                message: "runtime stop state blocked"
            )

        case (.stoppedVerified, .filesRemovalStarted):
            return RuntimeUninstallTransitionDecision(
                state: .filesRemovalStarted,
                persistedState: .filesRemovalStarted,
                message: "file removal started"
            )

        case (.filesRemovalStarted, .cleanupArtifactsObserved(let states)):
            let blockers = RuntimeUninstallReadinessPolicy.cleanupArtifactBlockers(states)
            if blockers.isEmpty {
                return RuntimeUninstallTransitionDecision(
                    state: .cleanupVerified,
                    commands: [.forgetPackageReceipts]
                )
            }
            return RuntimeUninstallTransitionDecision(
                state: .filesRemovalBlocked,
                persistedState: .filesRemovalBlocked,
                blockers: blockers,
                message: "file removal blocked"
            )

        case (.cleanupVerified, .receiptsForgetStarted):
            return RuntimeUninstallTransitionDecision(
                state: .receiptsForgetStarted,
                persistedState: .receiptsForgetStarted,
                message: "package receipt forget started"
            )

        case (.receiptsForgetStarted, .receiptForgetFailed(identifier: let identifier, reason: let reason)):
            let blockers = RuntimeUninstallReadinessPolicy.packageReceiptBlockers([
                .forgetFailed(identifier: identifier, reason: reason),
            ])
            return RuntimeUninstallTransitionDecision(
                state: .receiptsForgetBlocked,
                persistedState: .receiptsForgetBlocked,
                blockers: blockers,
                message: "package receipt forget blocked"
            )

        case (.receiptsForgetStarted, .packageReceiptsObserved(let states)):
            let blockers = RuntimeUninstallReadinessPolicy.packageReceiptBlockers(states)
            if blockers.isEmpty {
                return RuntimeUninstallTransitionDecision(
                    state: .completed,
                    persistedState: .completed,
                    commands: [.complete],
                    message: "uninstall completed"
                )
            }
            return RuntimeUninstallTransitionDecision(
                state: .receiptsForgetBlocked,
                persistedState: .receiptsForgetBlocked,
                blockers: blockers,
                message: "package receipt forget blocked"
            )

        default:
            throw RuntimeUninstallTransitionError(state: state, event: event)
        }
    }

    private static func stopBlockers(
        input: RuntimeUninstallReadinessInput,
        commandFailureReason: String
    ) -> [String] {
        let blockers = RuntimeUninstallReadinessPolicy.blockers(input: input)
        if blockers.isEmpty {
            return ["stop-runtime-services-failed:reason=\(commandFailureReason)"]
        }
        return blockers
    }
}
