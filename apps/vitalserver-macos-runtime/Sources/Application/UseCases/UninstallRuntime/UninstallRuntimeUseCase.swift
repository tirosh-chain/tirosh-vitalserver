import Foundation
import Contracts
import Domain
import Errors

public enum RuntimeConfiguredVitalFilesDirectorySource: Equatable, Sendable {
    case desired(revision: Int)
    case applied(revision: Int)

    public var diagnosticToken: String {
        switch self {
        case .desired(let revision):
            return "desired:revision=\(revision)"
        case .applied(let revision):
            return "applied:revision=\(revision)"
        }
    }
}

public struct RuntimeConfiguredVitalFilesDirectory: Equatable, Sendable {
    public let source: RuntimeConfiguredVitalFilesDirectorySource
    public let directory: URL

    public init(source: RuntimeConfiguredVitalFilesDirectorySource, directory: URL) {
        self.source = source
        self.directory = directory
    }
}

public struct RuntimeConfiguredVitalFilesDirectoriesSnapshot: Equatable, Sendable {
    public let revision: Int
    public let appliedRevision: Int?
    public let directories: [RuntimeConfiguredVitalFilesDirectory]

    public init(
        revision: Int,
        appliedRevision: Int?,
        directories: [RuntimeConfiguredVitalFilesDirectory]
    ) {
        self.revision = revision
        self.appliedRevision = appliedRevision
        self.directories = directories
    }
}

public enum RuntimeConfiguredVitalFilesDirectoriesUnavailableReason:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case hostSettingsMissing
    case hostSettingsReadFailed(reason: String)
    case configDecodeFailed(source: RuntimeConfiguredVitalFilesDirectorySource, reason: String)
    case pathMissing(source: RuntimeConfiguredVitalFilesDirectorySource)
    case pathInvalid(
        source: RuntimeConfiguredVitalFilesDirectorySource,
        path: String,
        reason: String
    )

    public var description: String {
        switch self {
        case .hostSettingsMissing:
            return "host-settings-missing"
        case .hostSettingsReadFailed(let reason):
            return "host-settings-read-failed:reason=\(reason)"
        case .configDecodeFailed(let source, let reason):
            return "vm-config-decode-failed:source=\(source.diagnosticToken):reason=\(reason)"
        case .pathMissing(let source):
            return "vital-files-path-missing:source=\(source.diagnosticToken)"
        case .pathInvalid(let source, let path, let reason):
            return "vital-files-path-invalid:source=\(source.diagnosticToken):path=\(path):reason=\(reason)"
        }
    }
}

public enum RuntimeConfiguredVitalFilesDirectoriesRead: Equatable, Sendable {
    case loaded(RuntimeConfiguredVitalFilesDirectoriesSnapshot)
    case unavailable(RuntimeConfiguredVitalFilesDirectoriesUnavailableReason)
}

public enum UninstallRuntimeVitalFilesDirectoryOwnership: Equatable, Sendable {
    case legacyManagedDefault
    case sharedManagedDefault
    case external
}

public struct UninstallRuntimeVitalFilesDirectory: Equatable, Sendable {
    public let directory: URL
    public let ownership: UninstallRuntimeVitalFilesDirectoryOwnership
    public let sources: [RuntimeConfiguredVitalFilesDirectorySource]

    public init(
        directory: URL,
        ownership: UninstallRuntimeVitalFilesDirectoryOwnership,
        sources: [RuntimeConfiguredVitalFilesDirectorySource]
    ) {
        self.directory = directory
        self.ownership = ownership
        self.sources = sources
    }
}

public struct UninstallRuntimeVitalFilesDirectories: Equatable, Sendable {
    public let revision: Int
    public let appliedRevision: Int?
    public let directories: [UninstallRuntimeVitalFilesDirectory]

    public init(
        revision: Int,
        appliedRevision: Int?,
        directories: [UninstallRuntimeVitalFilesDirectory]
    ) {
        self.revision = revision
        self.appliedRevision = appliedRevision
        self.directories = directories
    }
}

public enum UninstallRuntimeVitalFilesDirectoriesUnavailableReason:
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case ownerState(RuntimeConfiguredVitalFilesDirectoriesUnavailableReason)
    case ambiguousOverlap(
        path: String,
        boundary: String,
        sources: [RuntimeConfiguredVitalFilesDirectorySource]
    )

    public var description: String {
        switch self {
        case .ownerState(let reason):
            return reason.description
        case .ambiguousOverlap(let path, let boundary, let sources):
            let source = sources.map(\.diagnosticToken).joined(separator: "+")
            return "vital-files-path-ownership-ambiguous:path=\(path):boundary=\(boundary):source=\(source)"
        }
    }
}

public enum UninstallRuntimeVitalFilesDirectoriesResolution: Equatable, Sendable {
    case available(UninstallRuntimeVitalFilesDirectories)
    case unavailable(UninstallRuntimeVitalFilesDirectoriesUnavailableReason)
}

public enum UninstallRuntimeVitalFilesOwnership: Equatable, Sendable {
    case resolved(UninstallRuntimeVitalFilesDirectories)
    case destructiveRecoveryWithoutConfiguredOwnership(
        reason: UninstallRuntimeVitalFilesDirectoriesUnavailableReason
    )
}

public struct UninstallRuntimeStartPlan: Equatable, Sendable {
    public let startedLogMessage: String

    public init(startedLogMessage: String) {
        self.startedLogMessage = startedLogMessage
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
    public let vitalFilesDirectoryLogMessages: [String]

    public init(
        candidates: [UninstallRuntimePreserveCandidate],
        vitalFilesDirectoryLogMessages: [String]
    ) {
        self.candidates = candidates
        self.vitalFilesDirectoryLogMessages = vitalFilesDirectoryLogMessages
    }
}

public struct UninstallRuntimeRemovalPlan: Equatable, Sendable {
    public let targets: [URL]
    public let preservedExternalDirectoryLogMessages: [String]

    public init(targets: [URL], preservedExternalDirectoryLogMessages: [String]) {
        self.targets = targets
        self.preservedExternalDirectoryLogMessages = preservedExternalDirectoryLogMessages
    }
}

public enum UninstallRuntimeReceiptForgetDecision: Equatable, Sendable {
    case skip(logMessage: String)
    case forget(logMessage: String)
}

public enum UninstallRuntimeWorkflowLogStep: String, Sendable {
    case createVitalServerBackup = "create-vitalserver-backup"
    case stopLaunchdServices = "stop-launchd-services"
    case removePlists = "remove-plists"
    case removeInstalledFiles = "remove-installed-files"
    case removeRuntimeTools = "remove-runtime-tools"
    case restorePreservedUserData = "restore-preserved-user-data"
    case forgetPackageReceipt = "forget-package-receipt"
    case preserveUserData = "preserve-user-data"
}

public enum UninstallRuntimeWorkflowLogStepStatus: String, Sendable {
    case started
    case completed
}

public struct UninstallRuntimeProcessPlan: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public struct UninstallRuntimeUseCase {
    public init() {}

    public func startPlan(clean: Bool, forceClean: Bool) -> UninstallRuntimeStartPlan {
        UninstallRuntimeStartPlan(
            startedLogMessage: "uninstall started clean=\(clean) forceClean=\(forceClean)"
        )
    }

    public func shouldCreateVitalServerBackup(clean: Bool) -> Bool {
        !clean
    }

    public func stepLogMessage(
        step: UninstallRuntimeWorkflowLogStep,
        status: UninstallRuntimeWorkflowLogStepStatus
    ) -> String {
        "step=\(step.rawValue) status=\(status.rawValue)"
    }

    public func preserveRootDirectory(retainedDataRoot: URL, uniqueID: String) -> URL {
        retainedDataRoot.appendingPathComponent("tirosh-vitalserver-uninstall-\(uniqueID)")
    }

    public func retainedDataDirectoryAlreadyPresentMessage(path: String) -> String {
        "refusing to replace existing retained uninstall data path=\(path)"
    }

    public func retainedUserDataLogMessage(path: String) -> String {
        "retained standard uninstall data path=\(path) owner=uninstall-retained-data"
    }

    public func vitalServerBackupAbortLogMessage(reason: String) -> String {
        "standard uninstall aborted because VitalServer backup did not complete error=\(reason)"
    }

    public func configuredVitalFilesDirectoriesUnavailableMessage(blockers: [String]) -> String {
        "uninstall blocked because Vital files ownership is unavailable blockers=\(blockers.joined(separator: ","))"
    }

    public func forceCleanVitalFilesOwnershipOverrideLogMessage(reason: String) -> String {
        "force-clean destructive recovery override accepted unavailable Vital files ownership reason=\(reason) preservationLimit=only-known-managed-defaults-are-removed;configured-paths-cannot-be-proven"
    }

    public func configuredVitalFilesDirectoriesLoadedLogMessage(
        _ directories: UninstallRuntimeVitalFilesDirectories
    ) -> String {
        let appliedRevision = directories.appliedRevision.map(String.init) ?? "none"
        let paths = directories.directories.map { directory in
            let sources = directory.sources.map(\.diagnosticToken).joined(separator: "+")
            return "\(directory.directory.path)[\(sources)]"
        }.joined(separator: ",")
        return "configured Vital files ownership loaded revision=\(directories.revision) appliedRevision=\(appliedRevision) paths=\(paths)"
    }

    public func resolveVitalFilesDirectories(
        read: RuntimeConfiguredVitalFilesDirectoriesRead,
        productRoot: URL,
        legacyManagedDefault: URL,
        sharedManagedDefault: URL,
        retainedDataRoot: URL
    ) -> UninstallRuntimeVitalFilesDirectoriesResolution {
        let snapshot: RuntimeConfiguredVitalFilesDirectoriesSnapshot
        switch read {
        case .loaded(let loaded):
            snapshot = loaded
        case .unavailable(let reason):
            return .unavailable(.ownerState(reason))
        }

        let normalizedProductRoot = normalized(productRoot)
        let normalizedLegacyDefault = normalized(legacyManagedDefault)
        let normalizedSharedDefault = normalized(sharedManagedDefault)
        let normalizedRetainedRoot = normalized(retainedDataRoot)
        var resolved: [UninstallRuntimeVitalFilesDirectory] = []
        let sourcesByNormalizedPath = Dictionary(grouping: snapshot.directories) {
            normalized($0.directory).path
        }.mapValues { configured in
            configured.map(\.source)
        }

        for configured in snapshot.directories {
            let configuredDirectory = normalized(configured.directory)
            let configuredSources = sourcesByNormalizedPath[configuredDirectory.path] ?? [configured.source]
            let ownership: UninstallRuntimeVitalFilesDirectoryOwnership
            if configuredDirectory.path == normalizedLegacyDefault.path {
                ownership = .legacyManagedDefault
            } else if configuredDirectory.path == normalizedSharedDefault.path {
                ownership = .sharedManagedDefault
            } else if pathsOverlapCaseInsensitively(configuredDirectory, normalizedProductRoot) {
                return .unavailable(.ambiguousOverlap(
                    path: configuredDirectory.path,
                    boundary: normalizedProductRoot.path,
                    sources: configuredSources
                ))
            } else if pathsOverlapCaseInsensitively(configuredDirectory, normalizedLegacyDefault) {
                return .unavailable(.ambiguousOverlap(
                    path: configuredDirectory.path,
                    boundary: normalizedLegacyDefault.path,
                    sources: configuredSources
                ))
            } else if pathsOverlapCaseInsensitively(configuredDirectory, normalizedSharedDefault) {
                return .unavailable(.ambiguousOverlap(
                    path: configuredDirectory.path,
                    boundary: normalizedSharedDefault.path,
                    sources: configuredSources
                ))
            } else if pathsOverlapCaseInsensitively(configuredDirectory, normalizedRetainedRoot) {
                return .unavailable(.ambiguousOverlap(
                    path: configuredDirectory.path,
                    boundary: normalizedRetainedRoot.path,
                    sources: configuredSources
                ))
            } else {
                ownership = .external
            }

            if let index = resolved.firstIndex(where: { $0.directory.path == configuredDirectory.path }) {
                let existing = resolved[index]
                guard existing.sources.contains(configured.source) == false else {
                    continue
                }
                resolved[index] = UninstallRuntimeVitalFilesDirectory(
                    directory: existing.directory,
                    ownership: existing.ownership,
                    sources: existing.sources + [configured.source]
                )
            } else {
                resolved.append(UninstallRuntimeVitalFilesDirectory(
                    directory: configuredDirectory,
                    ownership: ownership,
                    sources: [configured.source]
                ))
            }
        }

        return .available(UninstallRuntimeVitalFilesDirectories(
            revision: snapshot.revision,
            appliedRevision: snapshot.appliedRevision,
            directories: resolved
        ))
    }

    public func preservePlan(
        productRoot: URL,
        legacyManagedDefaultVitalFilesDirectory: URL,
        vitalFilesOwnership: UninstallRuntimeVitalFilesOwnership
    ) -> UninstallRuntimePreservePlan {
        let candidates = [
            UninstallRuntimePreserveCandidate(source: productRoot.appendingPathComponent("logs"), token: "logs"),
            UninstallRuntimePreserveCandidate(source: productRoot.appendingPathComponent("backups"), token: "backups"),
            UninstallRuntimePreserveCandidate(
                source: productRoot.appendingPathComponent("vm/data/backups/redis"),
                token: "redis-backups"
            ),
            UninstallRuntimePreserveCandidate(
                source: legacyManagedDefaultVitalFilesDirectory,
                token: "legacy-vital-files"
            ),
        ]
        let logMessages: [String]
        switch vitalFilesOwnership {
        case .resolved(let vitalFilesDirectories):
            logMessages = vitalFilesDirectories.directories.compactMap {
                switch $0.ownership {
                case .legacyManagedDefault:
                    return nil
                case .sharedManagedDefault:
                    return "preserved shared managed default vital files directory in place path=\($0.directory.path)"
                case .external:
                    return "preserved external vital files directory in place path=\($0.directory.path)"
                }
            }
        case .destructiveRecoveryWithoutConfiguredOwnership(let reason):
            logMessages = [
                "configured Vital files ownership unavailable during destructive recovery reason=\(reason.description)",
            ]
        }
        return UninstallRuntimePreservePlan(
            candidates: candidates,
            vitalFilesDirectoryLogMessages: logMessages
        )
    }

    public func removalPlan(
        clean: Bool,
        managerApp: URL,
        legacyManagedDefaultVitalFilesDirectory: URL,
        sharedManagedDefaultVitalFilesDirectory: URL,
        retainedDataRoot: URL,
        vitalFilesOwnership: UninstallRuntimeVitalFilesOwnership
    ) -> UninstallRuntimeRemovalPlan {
        let logMessages: [String]
        switch vitalFilesOwnership {
        case .resolved(let vitalFilesDirectories):
            logMessages = clean
                ? vitalFilesDirectories.directories.compactMap {
                    guard $0.ownership == .external else { return nil }
                    return "preserved configured external vital files directory path=\($0.directory.path) reason=no-product-owned-removal-contract"
                }
                : []
        case .destructiveRecoveryWithoutConfiguredOwnership(let reason):
            logMessages = [
                "force-clean removed only known product-owned Vital files paths because configured ownership is unavailable reason=\(reason.description)",
            ]
        }
        return UninstallRuntimeRemovalPlan(
            targets: clean
                ? [
                    managerApp,
                    legacyManagedDefaultVitalFilesDirectory,
                    sharedManagedDefaultVitalFilesDirectory,
                    retainedDataRoot,
                ]
                : [managerApp],
            preservedExternalDirectoryLogMessages: logMessages
        )
    }

    private func normalized(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path).standardizedFileURL
    }

    private func pathsOverlapCaseInsensitively(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsPath = lhs.path.lowercased()
        let rhsPath = rhs.path.lowercased()
        if lhsPath == rhsPath {
            return true
        }
        return lhsPath.hasPrefix(rhsPath.hasSuffix("/") ? rhsPath : "\(rhsPath)/")
            || rhsPath.hasPrefix(lhsPath.hasSuffix("/") ? lhsPath : "\(lhsPath)/")
    }

    public func relocatedProductRoot(productRoot: URL, uniqueID: String) -> URL {
        productRoot
            .deletingLastPathComponent()
            .appendingPathComponent(".\(productRoot.lastPathComponent).uninstall-\(uniqueID)")
    }

    public func relocatedProductRootAlreadyPresentMessage(path: String) -> String {
        "refusing to replace existing uninstall tombstone path=\(path)"
    }

    public func relocatedProductRootLogMessage(source: String, destination: String) -> String {
        "relocated product root source=\(source) destination=\(destination)"
    }

    public func relocatedProductRootDisposalFailedMessage(path: String, reason: String) -> String {
        "uninstall completed but state-store tombstone disposal failed path=\(path) reason=\(reason)"
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

    public func removalTargetAlreadyAbsentLogMessage(path: String) -> String {
        "removal target already absent path=\(path)"
    }

    public func removalTargetPathInspectionFailedMessage(path: String, reason: String) -> String {
        "removal target path inspection failed target=\(path) reason=\(reason)"
    }

    public func removalTargetPathStateUnexpectedMessage(path: String, state: String) -> String {
        "removal target path state is unexpected target=\(path) state=\(state)"
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

    public func removalDiagnosticOpenFilePlan(executable: String, target: URL) -> UninstallRuntimeProcessPlan {
        UninstallRuntimeProcessPlan(executable: executable, arguments: ["+D", target.path])
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
