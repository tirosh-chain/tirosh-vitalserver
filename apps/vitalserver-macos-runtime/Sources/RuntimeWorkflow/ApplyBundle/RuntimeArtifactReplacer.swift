import Contracts
import Foundation

public struct RuntimeArtifactReplacementDestinations {
    public var managerApp: URL
    public var nginxBundle: URL
    public var guestDeploy: URL
    public var runtimeTools: URL

    public init(
        managerApp: URL,
        nginxBundle: URL,
        guestDeploy: URL,
        runtimeTools: URL
    ) {
        self.managerApp = managerApp
        self.nginxBundle = nginxBundle
        self.guestDeploy = guestDeploy
        self.runtimeTools = runtimeTools
    }
}

public struct RuntimeArtifactReplacementRules {
    public var tarCommand: String
    public var appBundleRoot: String
    public var nginxBundleRoot: String
    public var guestDeployRoot: String
    public var runtimeToolsAllowedRootEntries: Set<String>

    public init(
        tarCommand: String,
        appBundleRoot: String,
        nginxBundleRoot: String,
        guestDeployRoot: String,
        runtimeToolsAllowedRootEntries: Set<String>
    ) {
        self.tarCommand = tarCommand
        self.appBundleRoot = appBundleRoot
        self.nginxBundleRoot = nginxBundleRoot
        self.guestDeployRoot = guestDeployRoot
        self.runtimeToolsAllowedRootEntries = runtimeToolsAllowedRootEntries
    }
}

public struct RuntimeArtifactReplacer {
    public var destinations: RuntimeArtifactReplacementDestinations
    public var rules: RuntimeArtifactReplacementRules
    public var temporaryDirectory: URL
    public var fileExists: (URL) -> Bool
    public var directoryExists: (URL) -> Bool
    public var fileSize: (URL) throws -> UInt64
    public var createDirectory: (URL, Bool) throws -> Void
    public var removeItem: (URL) throws -> Void
    public var moveItem: (URL, URL) throws -> Void
    public var readUTF8Text: (URL) throws -> String
    public var runRequired: (String, [String]) throws -> Void
    public var runProcessToFile: (String, [String], URL) throws -> Void
    public var log: (String) -> Void

    public init(
        destinations: RuntimeArtifactReplacementDestinations,
        rules: RuntimeArtifactReplacementRules,
        temporaryDirectory: URL,
        fileExists: @escaping (URL) -> Bool,
        directoryExists: @escaping (URL) -> Bool,
        fileSize: @escaping (URL) throws -> UInt64,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        moveItem: @escaping (URL, URL) throws -> Void,
        readUTF8Text: @escaping (URL) throws -> String,
        runRequired: @escaping (String, [String]) throws -> Void,
        runProcessToFile: @escaping (String, [String], URL) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.destinations = destinations
        self.rules = rules
        self.temporaryDirectory = temporaryDirectory
        self.fileExists = fileExists
        self.directoryExists = directoryExists
        self.fileSize = fileSize
        self.createDirectory = createDirectory
        self.removeItem = removeItem
        self.moveItem = moveItem
        self.readUTF8Text = readUTF8Text
        self.runRequired = runRequired
        self.runProcessToFile = runProcessToFile
        self.log = log
    }

    public func replace(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
        for artifact in artifacts where artifact.type != .rootfsBase {
            let source = stagedBundle.appendingPathComponent(artifact.name)
            log(
                "artifact replacement started type=\(artifact.type.rawValue) name=\(artifact.name) source=\(source.path) size=\(formatBytes(bundleItemSize(artifact.size)))"
            )
            try validatePayload(artifact, source: source)
            switch artifact.type {
            case .appBundle:
                try replaceTarGz(source, destination: destinations.managerApp)
            case .nginxBundle:
                try replaceTarGz(source, destination: destinations.nginxBundle)
            case .guestDeploy:
                try replaceTarGz(source, destination: destinations.guestDeploy)
            case .runtimeTools:
                try extractTarGz(source, destination: destinations.runtimeTools)
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
            try validateTarGz(source, requiredTopLevel: rules.appBundleRoot)
        case .nginxBundle:
            try validateTarGz(source, requiredTopLevel: rules.nginxBundleRoot)
        case .guestDeploy:
            try validateTarGz(source, requiredTopLevel: rules.guestDeployRoot)
        case .runtimeTools:
            try validateTarGz(
                source,
                allowedRootEntries: rules.runtimeToolsAllowedRootEntries
            )
        default:
            throw bundleVerificationFailure("unsupported artifact type: \(artifact.type.rawValue)")
        }
    }

    private func replaceTarGz(_ source: URL, destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).update")
        log(
            "archive replacement started source=\(source.path) destination=\(destination.path) temporary=\(temporary.path) size=\(formatBytes(try fileSize(source)))"
        )
        if fileExists(temporary) || directoryExists(temporary) {
            try removeItem(temporary)
        }
        try createDirectory(temporary, true)
        try runRequired(rules.tarCommand, ["-xzf", source.path, "-C", temporary.path, "--strip-components", "1"])
        if fileExists(destination) || directoryExists(destination) {
            try removeItem(destination)
        }
        try moveItem(temporary, destination)
        log("archive replacement completed destination=\(destination.path)")
    }

    private func extractTarGz(_ source: URL, destination: URL) throws {
        log(
            "archive extraction started source=\(source.path) destination=\(destination.path) size=\(formatBytes(try fileSize(source)))"
        )
        try createDirectory(destination, true)
        try runRequired(rules.tarCommand, ["-xzf", source.path, "-C", destination.path])
        log("archive extraction completed destination=\(destination.path)")
    }

    private func validateTarGz(
        _ source: URL,
        requiredTopLevel: String? = nil,
        allowedRootEntries: Set<String>? = nil
    ) throws {
        let listOutput = temporaryDirectory
            .appendingPathComponent("tirosh-\(UUID().uuidString)-tar-list.txt")
        defer {
            removeTemporaryValidationOutput(listOutput)
        }
        try runProcessToFile(rules.tarCommand, ["-tzf", source.path], listOutput)
        let entries = try readUTF8Text(listOutput)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !entries.isEmpty else {
            throw bundleVerificationFailure("empty tar.gz: \(source.lastPathComponent)")
        }

        for entry in entries {
            try validateTarEntryName(entry, source: source)
            let rootEntry = entry.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? entry
            if let requiredTopLevel, rootEntry != requiredTopLevel {
                throw bundleVerificationFailure(
                    "unexpected top-level entry in \(source.lastPathComponent): \(rootEntry)"
                )
            }
            if let allowedRootEntries, !allowedRootEntries.contains(rootEntry) {
                throw bundleVerificationFailure(
                    "unexpected root entry in \(source.lastPathComponent): \(rootEntry)"
                )
            }
        }

        let verboseOutput = temporaryDirectory
            .appendingPathComponent("tirosh-\(UUID().uuidString)-tar-verbose.txt")
        defer {
            removeTemporaryValidationOutput(verboseOutput)
        }
        try runProcessToFile(rules.tarCommand, ["-tvzf", source.path], verboseOutput)
        let verboseText = try readUTF8Text(verboseOutput)
        for line in verboseText.split(separator: "\n") {
            guard let entryType = line.first else {
                continue
            }
            if entryType == "l" || entryType == "h" {
                throw bundleVerificationFailure(
                    "tar.gz must not contain links: \(source.lastPathComponent)"
                )
            }
        }
    }

    private func removeTemporaryValidationOutput(_ url: URL) {
        do {
            try removeItem(url)
        } catch {
            log("artifact validation temporary file cleanup failed path=\(url.path) error=\(error)")
        }
    }

    private func validateTarEntryName(_ entry: String, source: URL) throws {
        if entry.hasPrefix("/") || entry.contains("\0") {
            throw bundleVerificationFailure("unsafe tar entry in \(source.lastPathComponent): \(entry)")
        }
        let components = entry.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains("..") {
            throw bundleVerificationFailure("path traversal in \(source.lastPathComponent): \(entry)")
        }
    }

    private func bundleVerificationFailure(_ message: String) -> RuntimeWorkflowError {
        .operationFailed("bundle verification failed: \(message)")
    }

    private func bundleItemSize(_ size: Int) -> UInt64 {
        UInt64(max(size, 0))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
