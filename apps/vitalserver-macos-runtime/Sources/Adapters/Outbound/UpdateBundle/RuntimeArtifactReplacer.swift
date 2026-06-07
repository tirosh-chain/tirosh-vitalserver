import Contracts
import Foundation
import Errors

public struct RuntimeArtifactReplacer {
    public var destinations: RuntimeArtifactReplacementDestinations
    public var rules: RuntimeArtifactReplacementRules
    public var temporaryDirectory: URL
    public var pathState: (URL) -> RuntimePathState
    public var fileSize: (URL) throws -> UInt64
    public var createDirectory: (URL, Bool) throws -> Void
    public var removeItem: (URL) throws -> Void
    public var moveItem: (URL, URL) throws -> Void
    public var readUTF8Text: (URL) throws -> String
    public var runRequired: (String, [String]) throws -> Void
    public var runProcessToFile: (String, [String], URL) throws -> Void
    public var validateArchiveEntries: (String, String, String?, Set<String>?) throws -> Void
    public var validateArchiveEntryTypes: (String, String) throws -> Void
    public var archiveValidationFailureMessage: (Error, URL) -> String
    public var validationOutputID: () -> String
    public var log: (String) -> Void
    private var pathRemover: RuntimeArtifactReplacementPathRemover {
        RuntimeArtifactReplacementPathRemover(
            pathState: pathState,
            removeItem: removeItem
        )
    }
    private var archiveValidator: RuntimeArtifactArchiveValidator {
        RuntimeArtifactArchiveValidator(
            tarCommand: rules.tarCommand,
            temporaryDirectory: temporaryDirectory,
            readUTF8Text: readUTF8Text,
            runProcessToFile: runProcessToFile,
            validateArchiveEntries: validateArchiveEntries,
            validateArchiveEntryTypes: validateArchiveEntryTypes,
            archiveValidationFailureMessage: archiveValidationFailureMessage,
            validationOutputID: validationOutputID,
            removeTemporaryOutput: removeTemporaryValidationOutput
        )
    }
    private var payloadInstaller: RuntimeArtifactPayloadInstaller {
        RuntimeArtifactPayloadInstaller(
            tarCommand: rules.tarCommand,
            fileSize: fileSize,
            createDirectory: createDirectory,
            moveItem: moveItem,
            runRequired: runRequired,
            pathRemover: pathRemover,
            log: log
        )
    }

    public init(
        destinations: RuntimeArtifactReplacementDestinations,
        rules: RuntimeArtifactReplacementRules,
        temporaryDirectory: URL,
        pathState: @escaping (URL) -> RuntimePathState,
        fileSize: @escaping (URL) throws -> UInt64,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        readUTF8Text: @escaping (URL) throws -> String,
        runRequired: @escaping (String, [String]) throws -> Void,
        runProcessToFile: @escaping (String, [String], URL) throws -> Void,
        validateArchiveEntries: @escaping (String, String, String?, Set<String>?) throws -> Void,
        validateArchiveEntryTypes: @escaping (String, String) throws -> Void,
        archiveValidationFailureMessage: @escaping (Error, URL) -> String,
        validationOutputID: @escaping () -> String = { UUID().uuidString },
        log: @escaping (String) -> Void
    ) {
        self.destinations = destinations
        self.rules = rules
        self.temporaryDirectory = temporaryDirectory
        self.pathState = pathState
        self.fileSize = fileSize
        self.createDirectory = createDirectory
        self.removeItem = removeItem
        self.moveItem = moveItem
        self.readUTF8Text = readUTF8Text
        self.runRequired = runRequired
        self.runProcessToFile = runProcessToFile
        self.validateArchiveEntries = validateArchiveEntries
        self.validateArchiveEntryTypes = validateArchiveEntryTypes
        self.archiveValidationFailureMessage = archiveValidationFailureMessage
        self.validationOutputID = validationOutputID
        self.log = log
    }

    public func replace(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        for artifact in artifacts where artifact.type != .rootfsBase {
            let source = stagedBundle.appendingPathComponent(artifact.name)
            log(
                "artifact replacement started type=\(artifact.type.rawValue) name=\(artifact.name) source=\(source.path) size=\(RuntimeArtifactByteFormatter.formatBytes(bundleItemSize(artifact.size)))"
            )
            try validatePayload(artifact, source: source)
            switch artifact.type {
            case .appBundle:
                try payloadInstaller.replaceTarGz(source, destination: destinations.managerApp)
            case .nginxBundle:
                try payloadInstaller.replaceTarGz(source, destination: destinations.nginxBundle)
            case .guestDeploy:
                try payloadInstaller.replaceTarGz(source, destination: destinations.guestDeploy)
            case .runtimeTools:
                try payloadInstaller.extractTarGz(source, destination: destinations.runtimeTools)
            default:
                throw bundleVerificationFailure("unsupported artifact type: \(artifact.type.rawValue)")
            }
            log("artifact replacement completed type=\(artifact.type.rawValue) name=\(artifact.name)")
        }
    }

    public func validatePayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        switch artifact.type {
        case .rootfsBase:
            return
        case .appBundle:
            try archiveValidator.validateTarGz(source, requiredTopLevel: rules.archiveLayout.appBundleRoot)
        case .nginxBundle:
            try archiveValidator.validateTarGz(source, requiredTopLevel: rules.archiveLayout.nginxBundleRoot)
        case .guestDeploy:
            try archiveValidator.validateTarGz(source, requiredTopLevel: rules.archiveLayout.guestDeployRoot)
        case .runtimeTools:
            try archiveValidator.validateTarGz(
                source,
                allowedRootEntries: rules.archiveLayout.runtimeToolsAllowedRootEntries
            )
        default:
            throw bundleVerificationFailure("unsupported artifact type: \(artifact.type.rawValue)")
        }
    }

    private func removeTemporaryValidationOutput(_ url: URL) {
        do {
            try removeItem(url)
        } catch {
            log("artifact validation temporary file cleanup failed path=\(url.path) error=\(error)")
        }
    }

    private func bundleVerificationFailure(_ message: String) -> RuntimeArtifactReplacementError {
        .bundleVerificationFailed(message)
    }

    private func bundleItemSize(_ size: Int) -> UInt64 {
        UInt64(max(size, 0))
    }
}
