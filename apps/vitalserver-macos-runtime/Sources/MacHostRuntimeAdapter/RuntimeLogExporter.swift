import Foundation
import RuntimeControl
import Core
import Contracts

protocol RuntimeLogExporting: Sendable {
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
}

struct MacHostRuntimeLogExporter: RuntimeLogExporting, @unchecked Sendable {
    private let fileManager: FileManager
    private let logCollector: RuntimeLogCollecting
    private let productLogsDirectory: URL
    private let supplementalLogItems: [RuntimeLogExportSupplementalSource]
    private let rotatedSupplementalSets: [RuntimeLogExportRotatedSupplementalSet]
    private let archiveRunner: (String, [String]) async -> RuntimeCommandResult

    init(
        fileManager: FileManager = .default,
        logCollector: RuntimeLogCollecting = MacHostRuntimeLogCollector(),
        productLogsDirectory: URL = URL(fileURLWithPath: RuntimeAdapterConstants.Paths.productLogs),
        supplementalLogItems: [RuntimeLogExportSupplementalSource] = RuntimeLogExportSupplementalSource.defaultItems(),
        rotatedSupplementalSets: [RuntimeLogExportRotatedSupplementalSet] = RuntimeLogExportRotatedSupplementalSet.defaultSets(),
        archiveRunner: @escaping (String, [String]) async -> RuntimeCommandResult = ProcessRunner.run
    ) {
        self.fileManager = fileManager
        self.logCollector = logCollector
        self.productLogsDirectory = productLogsDirectory
        self.supplementalLogItems = supplementalLogItems
        self.rotatedSupplementalSets = rotatedSupplementalSets
        self.archiveRunner = archiveRunner
    }

    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        try logCollector.refreshLogCollection()

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("vitalserver-log-export-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingRoot)
        }

        let bundleRoot = stagingRoot.appendingPathComponent("vitalserver-logs", isDirectory: true)
        try copyLogItem(
            from: productLogsDirectory,
            to: bundleRoot
        )
        if !fileManager.fileExists(atPath: bundleRoot.path) {
            try fileManager.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        }
        try makeStagingBundleWritable(bundleRoot)
        try copySupplementalLogs(to: bundleRoot)
        try writeExportManifest(to: bundleRoot)

        let temporaryArchive = stagingRoot.appendingPathComponent(destination.lastPathComponent)
        let result = await archiveRunner(
            RuntimeAdapterConstants.Commands.ditto,
            ["-c", "-k", "--sequesterRsrc", "--keepParent", bundleRoot.path, temporaryArchive.path]
        )
        guard result.exitCode == 0 else {
            throw RuntimeClientError.logExportFailed(result.localSummary)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryArchive, to: destination)
        return RuntimeLogExportResult(destination: destination)
    }

    private func copyLogItem(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func makeStagingBundleWritable(_ bundleRoot: URL) throws {
        try makeStagingItemWritable(bundleRoot, isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: bundleRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        ) else {
            return
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            try makeStagingItemWritable(url, isDirectory: values.isDirectory == true)
        }
    }

    private func makeStagingItemWritable(_ url: URL, isDirectory: Bool) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        let writablePermissions = Int(permissions | (isDirectory ? 0o700 : 0o600))
        try fileManager.setAttributes([.posixPermissions: writablePermissions], ofItemAtPath: url.path)
    }

    private func copySupplementalLogs(to bundleRoot: URL) throws {
        for item in supplementalLogItems {
            try copySupplementalLog(item, to: bundleRoot)
        }
        for set in rotatedSupplementalSets {
            try copyRotatedSupplementalLogs(set, to: bundleRoot)
        }
    }

    private func copySupplementalLog(_ item: RuntimeLogExportSupplementalSource, to bundleRoot: URL) throws {
        guard fileManager.fileExists(atPath: item.source.path) else {
            return
        }
        let destination = bundleRoot.appendingPathComponent(item.relativeDestination)
        guard !fileManager.fileExists(atPath: destination.path) else {
            return
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: item.source, to: destination)
    }

    private func copyRotatedSupplementalLogs(_ set: RuntimeLogExportRotatedSupplementalSet, to bundleRoot: URL) throws {
        guard fileManager.fileExists(atPath: set.sourceDirectory.path) else {
            return
        }
        let entries = try fileManager.contentsOfDirectory(
            at: set.sourceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for source in entries where source.lastPathComponent.hasPrefix(set.sourceFilePrefix) {
            let suffix = String(source.lastPathComponent.dropFirst(set.sourceFilePrefix.count))
            guard !suffix.isEmpty else {
                continue
            }
            let destination = bundleRoot
                .appendingPathComponent(set.relativeDestinationDirectory)
                .appendingPathComponent("\(set.destinationFilePrefix)\(suffix)")
            guard !fileManager.fileExists(atPath: destination.path) else {
                continue
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private func writeExportManifest(to bundleRoot: URL) throws {
        let manifest = RuntimeLogExportManifest(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            productLogsDirectory: productLogsDirectory.path,
            supplementalItems: supplementalLogItems.map { item in
                RuntimeLogExportManifest.SupplementalItem(
                    source: item.source.path,
                    relativeDestination: item.relativeDestination,
                    sourcePresent: fileManager.fileExists(atPath: item.source.path),
                    included: fileManager.fileExists(
                        atPath: bundleRoot.appendingPathComponent(item.relativeDestination).path
                    )
                )
            }
        )
        let diagnosticsDirectory = bundleRoot.appendingPathComponent("diagnostics", isDirectory: true)
        try fileManager.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: diagnosticsDirectory.appendingPathComponent("export-manifest.json"),
            options: .atomic
        )
    }
}

struct RuntimeLogExportManifest: Codable, Equatable {
    struct SupplementalItem: Codable, Equatable {
        let source: String
        let relativeDestination: String
        let sourcePresent: Bool
        let included: Bool
    }

    let generatedAt: String
    let productLogsDirectory: String
    let supplementalItems: [SupplementalItem]
}

private extension RuntimeCommandResult {
    var localSummary: String {
        let output = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if output.isEmpty {
            return exitCode == 0
                ? "Done"
                : "Command failed with exit code \(exitCode)"
        }
        return output
    }
}

struct RuntimeLogExportSupplementalSource {
    let source: URL
    let relativeDestination: String

    init(source: URL, relativeDestination: String) {
        self.source = source
        self.relativeDestination = relativeDestination
    }

    static func defaultItems() -> [RuntimeLogExportSupplementalSource] {
        [
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.bootstrapLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.bootstrapLog)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.containerLogSource),
                relativeDestination: "guest/container-logs.log"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.updateActivationLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.updateActivationLog)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.updateShutdownLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.updateShutdownLog)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.datastoreRepairLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.datastoreRepairLog)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.redisBackupLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.redisBackupLog)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.commandLogFile),
                relativeDestination: "command.log"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeStatus),
                relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeStatus)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeEvents),
                relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeEvents)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeObservabilityDB),
                relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: "\(RuntimeAdapterConstants.Paths.runtimeObservabilityDB)-wal"),
                relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)-wal"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: "\(RuntimeAdapterConstants.Paths.runtimeObservabilityDB)-shm"),
                relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)-shm"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeState),
                relativeDestination: "diagnostics/guest/\(RuntimeFileNames.runtimeState)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.vmIPFile),
                relativeDestination: "diagnostics/guest/\(RuntimeFileNames.vmIP)"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.vmConfig),
                relativeDestination: "diagnostics/runtime/vm-config.json"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeVersion),
                relativeDestination: "diagnostics/runtime/runtime-version.json"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.guestRuntimeConfig),
                relativeDestination: "diagnostics/guest/runtime-config.json"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.proxyLaunchDaemon),
                relativeDestination: "diagnostics/host/com.tirosh.vitalserver-proxy.plist"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.proxyNginxConfig),
                relativeDestination: "diagnostics/host/vitalserver-nginx.conf"
            ),
            RuntimeLogExportSupplementalSource(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.proxyNginxPid),
                relativeDestination: "diagnostics/host/nginx.pid"
            ),
        ]
    }
}

struct RuntimeLogExportRotatedSupplementalSet {
    let sourceDirectory: URL
    let sourceFilePrefix: String
    let relativeDestinationDirectory: String
    let destinationFilePrefix: String

    init(
        sourceDirectory: URL,
        sourceFilePrefix: String,
        relativeDestinationDirectory: String,
        destinationFilePrefix: String
    ) {
        self.sourceDirectory = sourceDirectory
        self.sourceFilePrefix = sourceFilePrefix
        self.relativeDestinationDirectory = relativeDestinationDirectory
        self.destinationFilePrefix = destinationFilePrefix
    }

    static func defaultSets() -> [RuntimeLogExportRotatedSupplementalSet] {
        [
            RuntimeLogExportRotatedSupplementalSet(
                sourceDirectory: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.guestRunDirectory),
                sourceFilePrefix: "container-logs.log.",
                relativeDestinationDirectory: "guest",
                destinationFilePrefix: "container-logs.log."
            ),
            RuntimeLogExportRotatedSupplementalSet(
                sourceDirectory: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeEvents)
                    .deletingLastPathComponent(),
                sourceFilePrefix: "\(RuntimeFileNames.runtimeEvents).",
                relativeDestinationDirectory: "diagnostics/status",
                destinationFilePrefix: "\(RuntimeFileNames.runtimeEvents)."
            ),
        ]
    }
}
