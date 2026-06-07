import Contracts
import Foundation


public struct RuntimeInstallTransitionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let state: String
    public let event: String
    public let reason: String

    public init<State, Event>(
        state: State,
        event: Event,
        reason: String = "invalid install transition"
    ) {
        self.state = String(describing: state)
        self.event = String(describing: event)
        self.reason = reason
    }

    public var description: String {
        "\(reason) state=\(state) event=\(event)"
    }
}


public struct RuntimeOperationPlanValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let operation: RuntimeOperation
    public let invalidSteps: [RuntimeWorkflowStep]

    public init(operation: RuntimeOperation, invalidSteps: [RuntimeWorkflowStep]) {
        self.operation = operation
        self.invalidSteps = invalidSteps
    }

    public var description: String {
        let stepNames = invalidSteps.map(\.rawValue).joined(separator: ", ")
        return "invalid steps for \(operation.rawValue): \(stepNames)"
    }
}


public struct RuntimeUninstallTransitionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let state: String
    public let event: String

    public init<State, Event>(state: State, event: Event) {
        self.state = String(describing: state)
        self.event = String(describing: event)
    }

    public var description: String {
        "invalid uninstall transition state=\(state) event=\(event)"
    }
}


public enum RuntimeUpdateCompatibilityError: Error, Equatable, CustomStringConvertible {
    case updaterTooOld(currentVersion: String, minimumVersion: String)
    case unsupportedChannel(currentChannel: UpdateBundleChannel, bundleChannel: UpdateBundleChannel)
    case twoPhaseUpdateRequired
    case unsupportedPlatform(currentPlatform: String, targetPlatform: String)
    case guestActivationRequirementMismatch(requiresGuestActivation: Bool, hasGuestDeployArtifact: Bool)

    public var description: String {
        switch self {
        case let .updaterTooOld(currentVersion, minimumVersion):
            return "update bundle requires updater \(minimumVersion) or newer; current updater is \(currentVersion)"
        case let .unsupportedChannel(currentChannel, bundleChannel):
            return "update bundle channel \(bundleChannel.rawValue) is not compatible with installed channel \(currentChannel.rawValue)"
        case .twoPhaseUpdateRequired:
            return "update bundle requires a bridge/two-phase update"
        case let .unsupportedPlatform(currentPlatform, targetPlatform):
            return "update bundle targets \(targetPlatform); current platform is \(currentPlatform)"
        case let .guestActivationRequirementMismatch(requiresGuestActivation, hasGuestDeployArtifact):
            return "update bundle guest activation flag mismatch: requiresGuestActivation=\(requiresGuestActivation), hasGuestDeployArtifact=\(hasGuestDeployArtifact)"
        }
    }
}


public enum UpdateBundleArchiveVerificationError: Error, Equatable, CustomStringConvertible {
    case emptyArchive
    case unsafePath(String)
    case multipleRootDirectories
    case containsLink(String)
    case containsUnsupportedEntry(String, String)

    public var description: String {
        switch self {
        case .emptyArchive:
            return "empty update bundle archive"
        case .unsafePath(let path):
            return "unsafe update bundle archive path: \(path)"
        case .multipleRootDirectories:
            return "update bundle archive must contain a single root directory"
        case .containsLink(let archiveName):
            return "update bundle archive must not contain links: \(archiveName)"
        case .containsUnsupportedEntry(let archiveName, let entryType):
            return "update bundle archive must contain only regular files and directories: \(archiveName) entryType=\(entryType)"
        }
    }
}


public enum UpdateBundleVerificationError: Error, Equatable {
    case unsupportedSchema(Int)
    case unsupportedProduct(String)
    case invalidArtifactName(String)
    case invalidMigrationName(String)
    case unsupportedArtifactType(String)
    case manifestChecksumMismatch(String)
    case checksumFileMismatch(String)
    case sizeMismatch(String)
}
