import Foundation
import RuntimeControl
import Core
import Contracts

@MainActor
protocol RuntimeLogExporting {
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
}

@MainActor
struct MacHostRuntimeLogExporter: RuntimeLogExporting {
    private let fileManager: FileManager
    private let logCollector: RuntimeLogCollecting
    private let productLogsDirectory: URL
    private let fallbackLogItems: [RuntimeLogExportFallback]
    private let rotatedFallbackSets: [RuntimeLogExportRotatedFallbackSet]
    private let archiveRunner: (String, [String]) async -> RuntimeCommandResult

    init(
        fileManager: FileManager = .default,
        logCollector: RuntimeLogCollecting = MacHostRuntimeLogCollector(),
        productLogsDirectory: URL = URL(fileURLWithPath: RuntimeAdapterConstants.Paths.productLogs),
        fallbackLogItems: [RuntimeLogExportFallback] = RuntimeLogExportFallback.defaultItems(),
        rotatedFallbackSets: [RuntimeLogExportRotatedFallbackSet] = RuntimeLogExportRotatedFallbackSet.defaultSets(),
        archiveRunner: @escaping (String, [String]) async -> RuntimeCommandResult = ProcessRunner.run
    ) {
        self.fileManager = fileManager
        self.logCollector = logCollector
        self.productLogsDirectory = productLogsDirectory
        self.fallbackLogItems = fallbackLogItems
        self.rotatedFallbackSets = rotatedFallbackSets
        self.archiveRunner = archiveRunner
    }

    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        logCollector.refreshLogCollection()

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
        try copyFallbackLogs(to: bundleRoot)

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

    private func copyFallbackLogs(to bundleRoot: URL) throws {
        for item in fallbackLogItems {
            try copyFallbackLog(item, to: bundleRoot)
        }
        for set in rotatedFallbackSets {
            try copyRotatedFallbackLogs(set, to: bundleRoot)
        }
    }

    private func copyFallbackLog(_ item: RuntimeLogExportFallback, to bundleRoot: URL) throws {
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

    private func copyRotatedFallbackLogs(_ set: RuntimeLogExportRotatedFallbackSet, to bundleRoot: URL) throws {
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

struct RuntimeLogExportFallback {
    let source: URL
    let relativeDestination: String

    init(source: URL, relativeDestination: String) {
        self.source = source
        self.relativeDestination = relativeDestination
    }

    static func defaultItems() -> [RuntimeLogExportFallback] {
        [
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.bootstrapLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.bootstrapLog)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.containerLogSource),
                relativeDestination: "guest/container-logs.log"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.updateActivationLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.updateActivationLog)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.datastoreRepairLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.datastoreRepairLog)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.redisBackupLogSource),
                relativeDestination: "guest/\(RuntimeFileNames.redisBackupLog)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.commandLogFile),
                relativeDestination: "command.log"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeStatus),
                relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeStatus)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeEvents),
                relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeEvents)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeObservabilityDB),
                relativeDestination: "diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeState),
                relativeDestination: "diagnostics/guest/\(RuntimeFileNames.runtimeState)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.vmIPFile),
                relativeDestination: "diagnostics/guest/\(RuntimeFileNames.vmIP)"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.vmConfig),
                relativeDestination: "diagnostics/runtime/vm-config.json"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeVersion),
                relativeDestination: "diagnostics/runtime/runtime-version.json"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.guestRuntimeConfig),
                relativeDestination: "diagnostics/guest/runtime-config.json"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.proxyLaunchDaemon),
                relativeDestination: "diagnostics/host/com.tirosh.vitalserver-proxy.plist"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.proxyNginxConfig),
                relativeDestination: "diagnostics/host/vitalserver-nginx.conf"
            ),
            RuntimeLogExportFallback(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.proxyNginxPid),
                relativeDestination: "diagnostics/host/nginx.pid"
            ),
        ]
    }
}

struct RuntimeLogExportRotatedFallbackSet {
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

    static func defaultSets() -> [RuntimeLogExportRotatedFallbackSet] {
        [
            RuntimeLogExportRotatedFallbackSet(
                sourceDirectory: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.guestRunDirectory),
                sourceFilePrefix: "container-logs.log.",
                relativeDestinationDirectory: "guest",
                destinationFilePrefix: "container-logs.log."
            ),
        ]
    }
}
