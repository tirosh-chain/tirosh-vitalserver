import Foundation
import Management
import Core
import Contracts

@MainActor
protocol RuntimeLogExporting {
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
}

@MainActor
struct LocalRuntimeLogExporter: RuntimeLogExporting {
    private let fileManager: FileManager
    private let logCollector: RuntimeLogCollecting
    private let productLogsDirectory: URL
    private let fallbackLogItems: [RuntimeLogExportFallback]
    private let rotatedFallbackSets: [RuntimeLogExportRotatedFallbackSet]
    private let archiveRunner: (String, [String]) async -> ProcessResult

    init(
        fileManager: FileManager = .default,
        logCollector: RuntimeLogCollecting = LocalRuntimeLogCollector(),
        productLogsDirectory: URL = URL(fileURLWithPath: RuntimeAdapterConstants.Paths.productLogs),
        fallbackLogItems: [RuntimeLogExportFallback] = RuntimeLogExportFallback.defaultItems(),
        rotatedFallbackSets: [RuntimeLogExportRotatedFallbackSet] = RuntimeLogExportRotatedFallbackSet.defaultSets(),
        archiveRunner: @escaping (String, [String]) async -> ProcessResult = ProcessRunner.run
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
            throw RuntimeClientError.logExportFailed(result.summary)
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
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.commandLogFile),
                relativeDestination: "command.log"
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
