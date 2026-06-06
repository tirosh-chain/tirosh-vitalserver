import Foundation
import Contracts
import Domain
import Errors

public struct UninstallRuntimeStartPlan: Equatable, Sendable {
    public let startedLogMessage: String
    public let configuredDirectoryReadFailureLogMessage: String?

    public init(startedLogMessage: String, configuredDirectoryReadFailureLogMessage: String?) {
        self.startedLogMessage = startedLogMessage
        self.configuredDirectoryReadFailureLogMessage = configuredDirectoryReadFailureLogMessage
    }
}

public struct UninstallRuntimePreserveCandidate: Equatable, Sendable {
    public let source: URL
    public let token: String

    public init(source: URL, token: String) {
        self.source = source
        self.token = token
    }
}

public struct UninstallRuntimePreservePlan: Equatable, Sendable {
    public let candidates: [UninstallRuntimePreserveCandidate]
    public let externalDirectoryLogMessage: String?
    public let configuredDirectoryReadFailureLogMessage: String?

    public init(
        candidates: [UninstallRuntimePreserveCandidate],
        externalDirectoryLogMessage: String?,
        configuredDirectoryReadFailureLogMessage: String?
    ) {
        self.candidates = candidates
        self.externalDirectoryLogMessage = externalDirectoryLogMessage
        self.configuredDirectoryReadFailureLogMessage = configuredDirectoryReadFailureLogMessage
    }
}

public struct UninstallRuntimeRemovalPlan: Equatable, Sendable {
    public let targets: [URL]
    public let skippedExternalDirectoryLogMessage: String?

    public init(targets: [URL], skippedExternalDirectoryLogMessage: String?) {
        self.targets = targets
        self.skippedExternalDirectoryLogMessage = skippedExternalDirectoryLogMessage
    }
}

public enum UninstallRuntimeReceiptForgetDecision: Equatable, Sendable {
    case skip(logMessage: String)
    case forget(logMessage: String)
}

public struct UninstallRuntimeUseCase {
    public init() {}

    public func startPlan(clean: Bool, configuredDirectoryReadFailure: String?) -> UninstallRuntimeStartPlan {
        UninstallRuntimeStartPlan(
            startedLogMessage: "uninstall started clean=\(clean)",
            configuredDirectoryReadFailureLogMessage: configuredDirectoryReadFailure.map {
                "configured vital files directory unavailable reason=\($0)"
            }
        )
    }

    public func shouldCreateRedisBackup(clean: Bool) -> Bool {
        !clean
    }

    public func stepLogMessage(step: String, status: String) -> String {
        "step=\(step) status=\(status)"
    }

    public func redisBackupAbortLogMessage(reason: String) -> String {
        "standard uninstall aborted because Redis backup did not complete error=\(reason)"
    }

    public func preservePlan(
        productRoot: URL,
        defaultVitalFilesDirectory: URL,
        externalVitalFilesDirectory: URL?,
        configuredVitalFilesDirectoryReadFailure: String?
    ) -> UninstallRuntimePreservePlan {
        var candidates = [
            UninstallRuntimePreserveCandidate(source: productRoot.appendingPathComponent("logs"), token: "logs"),
            UninstallRuntimePreserveCandidate(source: productRoot.appendingPathComponent("backups"), token: "backups"),
            UninstallRuntimePreserveCandidate(
                source: productRoot.appendingPathComponent("vm/data/backups/redis"),
                token: "redis-backups"
            ),
        ]
        if externalVitalFilesDirectory == nil {
            candidates.append(UninstallRuntimePreserveCandidate(source: defaultVitalFilesDirectory, token: "vital-files"))
        }
        return UninstallRuntimePreservePlan(
            candidates: candidates,
            externalDirectoryLogMessage: externalVitalFilesDirectory.map {
                "preserved external vital files directory=\($0.path)"
            },
            configuredDirectoryReadFailureLogMessage: externalVitalFilesDirectory == nil
                ? configuredVitalFilesDirectoryReadFailure.map {
                    "preserving default vital files directory because configured external directory is unavailable reason=\($0)"
                }
                : nil
        )
    }

    public func removalPlan(
        clean: Bool,
        managerApp: URL,
        productRoot: URL,
        externalVitalFilesDirectory: URL?,
        configuredVitalFilesDirectoryReadFailure: String?
    ) -> UninstallRuntimeRemovalPlan {
        var targets = [managerApp, productRoot]
        var skippedExternalDirectoryLogMessage: String?
        if clean, let externalVitalFilesDirectory {
            targets.append(externalVitalFilesDirectory)
        } else if clean, let configuredVitalFilesDirectoryReadFailure {
            skippedExternalDirectoryLogMessage = "skipping external vital files directory cleanup because configured path is unavailable reason=\(configuredVitalFilesDirectoryReadFailure)"
        }
        return UninstallRuntimeRemovalPlan(
            targets: targets,
            skippedExternalDirectoryLogMessage: skippedExternalDirectoryLogMessage
        )
    }

    public func fileRemovalBlockers(
        removalFailureReason: String,
        preservedRestoreFailureReason: String?
    ) -> [String] {
        var blockers = ["file-removal-failed:reason=\(removalFailureReason)"]
        if let preservedRestoreFailureReason {
            blockers.append("restore-preserved-user-data-failed:reason=\(preservedRestoreFailureReason)")
        }
        return blockers
    }

    public func restoringPreservedUserDataAfterFailureLogMessage() -> String {
        "restoring preserved user data after uninstall failure"
    }

    public func preservedUserDataRestoreFailedLogMessage(reason: String) -> String {
        "preserved user data restore failed error=\(reason)"
    }

    public func fileRemovalBlockedMessage() -> String {
        "file removal blocked"
    }

    public func preservedSourceLogMessage(path: String) -> String {
        "preserved source=\(path)"
    }

    public func restoredPreservedLogMessage(path: String) -> String {
        "restored preserved=\(path)"
    }

    public func unsafeRemovalTargetFailureMessage(path: String) -> String {
        "refusing unsafe removal target=\(path)"
    }

    public func removalIncompleteFailureMessage(path: String) -> String {
        "removal incomplete target=\(path)"
    }

    public func removalDiagnosticTargetLogMessage(path: String) -> String {
        "removal diagnostic target=\(path)"
    }

    public func removalDiagnosticResidualLogMessage(path: String) -> String {
        "removal diagnostic residual path=\(path)"
    }

    public func removalDiagnosticContentsReadFailedLogMessage(path: String, reason: String) -> String {
        "removal diagnostic contents read failed target=\(path) error=\(reason)"
    }

    public func removalDiagnosticOpenFileLogMessage(line: String) -> String {
        "removal diagnostic open file \(line)"
    }

    public func removalDiagnosticOpenFileStderrLogMessage(stderr: String) -> String {
        "removal diagnostic lsof stderr=\(stderr)"
    }

    public func packageReceiptStateMap(
        _ states: [RuntimePackageReceiptState]
    ) -> [String: RuntimePackageReceiptState] {
        Dictionary(uniqueKeysWithValues: states.compactMap { state -> (String, RuntimePackageReceiptState)? in
            switch state {
            case .present(let identifier),
                 .absent(let identifier),
                 .readFailed(let identifier, _),
                 .forgetFailed(let identifier, _):
                return (identifier, state)
            case .unknown:
                return nil
            }
        })
    }

    public func receiptForgetDecision(
        identifier: String,
        observedReceiptStates: [String: RuntimePackageReceiptState]
    ) -> UninstallRuntimeReceiptForgetDecision {
        if case .absent = observedReceiptStates[identifier] {
            return .skip(logMessage: "package receipt already absent identifier=\(identifier)")
        }
        return .forget(logMessage: "forget package receipt identifier=\(identifier)")
    }

    public func processFailureReason(_ result: RuntimeProcessResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return "exitCode=\(result.exitCode) stderr=\(stderr)"
        }
        if !stdout.isEmpty {
            return "exitCode=\(result.exitCode) stdout=\(stdout)"
        }
        return "exitCode=\(result.exitCode)"
    }

    public func packageReceiptForgetFailureMessage(identifier: String, reason: String) -> String {
        "package receipt forget failed identifier=\(identifier) \(reason)"
    }

    public func packageReceiptVerificationFailedMessage(blockers: [String]) -> String {
        "package receipt forget verification failed blockers=\(blockers.joined(separator: ","))"
    }

    public func runtimeStopBlockedFailureMessage(blockers: [String]) -> String {
        "runtime stop state blocked blockers=\(blockers.joined(separator: ","))"
    }

    public func cleanupArtifactsRemainFailureMessage(blockers: [String]) -> String {
        "runtime cleanup artifacts remain blockers=\(blockers.joined(separator: ","))"
    }

    public func completedLogMessage() -> String {
        "uninstall completed"
    }

    public func transition(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        expectedCommands: [RuntimeUninstallWorkflowCommand]
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try RuntimeUninstallTransitionPolicy.transition(
            from: state,
            event: event
        )
        try requireCommands(expectedCommands, in: decision)
        return decision
    }

    public func transition(
        from state: RuntimeUninstallWorkflowState,
        event: RuntimeUninstallWorkflowEvent,
        expectedCommandsWhenAllowed: [RuntimeUninstallWorkflowCommand]
    ) throws -> RuntimeUninstallTransitionDecision {
        let decision = try RuntimeUninstallTransitionPolicy.transition(
            from: state,
            event: event
        )
        try requireCommands(
            decision.blockers.isEmpty ? expectedCommandsWhenAllowed : [],
            in: decision
        )
        return decision
    }

    public func requireCommands(
        _ expectedCommands: [RuntimeUninstallWorkflowCommand],
        in decision: RuntimeUninstallTransitionDecision
    ) throws {
        guard decision.commands == expectedCommands else {
            throw UninstallRuntimeUseCaseError.operationFailed(
                "unexpected uninstall workflow commands state=\(decision.state) expected=\(expectedCommands) actual=\(decision.commands)"
            )
        }
    }
}
