import Foundation
import Core
import Contracts

struct RuntimeArtifactReplacementDestinations {
    var managerApp: URL
    var nginxBundle: URL
    var guestDeploy: URL
    var runtimeTools: URL
}

struct RuntimeArtifactReplacer {
    var destinations: RuntimeArtifactReplacementDestinations
    var temporaryDirectory: URL
    var fileExists: (URL) -> Bool
    var directoryExists: (URL) -> Bool
    var fileSize: (URL) throws -> UInt64
    var createDirectory: (URL, Bool) throws -> Void
    var removeItem: (URL) throws -> Void
    var moveItem: (URL, URL) throws -> Void
    var readUTF8Text: (URL) throws -> String
    var runRequired: (String, [String]) throws -> Void
    var runProcessToFile: (String, [String], URL) throws -> Void
    var log: (String) -> Void

    func replace(_ artifacts: [UpdateBundleArtifact], stagedBundle: URL) throws {
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
                throw LauncherError.bundleVerificationFailed("unsupported artifact type: \(artifact.type.rawValue)")
            }
            log("artifact replacement completed type=\(artifact.type.rawValue) name=\(artifact.name)")
        }
    }

    func validatePayload(_ artifact: UpdateBundleArtifact, source: URL) throws {
        switch artifact.type {
        case .rootfsBase:
            return
        case .appBundle:
            try validateTarGz(source, requiredTopLevel: Constants.Product.managerAppName)
        case .nginxBundle:
            try validateTarGz(source, requiredTopLevel: "nginx")
        case .guestDeploy:
            try validateTarGz(source, requiredTopLevel: "deploy")
        case .runtimeTools:
            try validateTarGz(
                source,
                allowedRootEntries: [
                    "vitalserver-vm",
                    "vitalserver-proxy-run",
                    URL(fileURLWithPath: Constants.InstallPaths.uninstall).lastPathComponent,
                ]
            )
        default:
            throw LauncherError.bundleVerificationFailed("unsupported artifact type: \(artifact.type.rawValue)")
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
        try runRequired(Constants.Commands.tar, ["-xzf", source.path, "-C", temporary.path, "--strip-components", "1"])
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
        try runRequired(Constants.Commands.tar, ["-xzf", source.path, "-C", destination.path])
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
        try runProcessToFile(Constants.Commands.tar, ["-tzf", source.path], listOutput)
        let entries = try readUTF8Text(listOutput)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !entries.isEmpty else {
            throw LauncherError.bundleVerificationFailed("empty tar.gz: \(source.lastPathComponent)")
        }

        for entry in entries {
            try validateTarEntryName(entry, source: source)
            let rootEntry = entry.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? entry
            if let requiredTopLevel, rootEntry != requiredTopLevel {
                throw LauncherError.bundleVerificationFailed(
                    "unexpected top-level entry in \(source.lastPathComponent): \(rootEntry)"
                )
            }
            if let allowedRootEntries, !allowedRootEntries.contains(rootEntry) {
                throw LauncherError.bundleVerificationFailed(
                    "unexpected root entry in \(source.lastPathComponent): \(rootEntry)"
                )
            }
        }

        let verboseOutput = temporaryDirectory
            .appendingPathComponent("tirosh-\(UUID().uuidString)-tar-verbose.txt")
        defer {
            removeTemporaryValidationOutput(verboseOutput)
        }
        try runProcessToFile(Constants.Commands.tar, ["-tvzf", source.path], verboseOutput)
        let verboseText = try readUTF8Text(verboseOutput)
        for line in verboseText.split(separator: "\n") {
            guard let entryType = line.first else {
                continue
            }
            if entryType == "l" || entryType == "h" {
                throw LauncherError.bundleVerificationFailed(
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
            throw LauncherError.bundleVerificationFailed("unsafe tar entry in \(source.lastPathComponent): \(entry)")
        }
        let components = entry.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains("..") {
            throw LauncherError.bundleVerificationFailed("path traversal in \(source.lastPathComponent): \(entry)")
        }
    }

    private func bundleItemSize(_ size: Int) -> UInt64 {
        UInt64(max(size, 0))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
