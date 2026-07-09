import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

protocol RuntimeLogExporting: Sendable {
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
}

struct MacRuntimeControlLogExporter: RuntimeLogExporting, @unchecked Sendable {
    private let fileManager: FileManager
    private let logCollector: RuntimeLogCollecting
    private let productLogsDirectory: URL
    private let supplementalLogItems: [RuntimeLogExportSupplementalSource]
    private let rotatedSupplementalSets: [RuntimeLogExportRotatedSupplementalSet]
    private let temporaryDirectory: URL?
    private let exportID: @Sendable () -> String
    private let generatedAt: @Sendable () -> String
    private let archiveRunner: (String, [String]) async -> RuntimeCommandResult
    private var pathInspector: RuntimeLogExportPathInspector {
        RuntimeLogExportPathInspector(fileManager: fileManager)
    }
    private var stagingPermissionWriter: RuntimeLogExportStagingPermissionWriter {
        RuntimeLogExportStagingPermissionWriter(fileManager: fileManager)
    }

    init(
        fileManager: FileManager = .default,
        logCollector: RuntimeLogCollecting = MacRuntimeControlLogCollector(),
        productLogsDirectory: URL = InstalledRuntimePaths.defaultInstalled.productLogsDirectory,
        supplementalLogItems: [RuntimeLogExportSupplementalSource] = RuntimeLogExportSupplementalSource.defaultItems(),
        rotatedSupplementalSets: [RuntimeLogExportRotatedSupplementalSet] = RuntimeLogExportRotatedSupplementalSet.defaultSets(),
        temporaryDirectory: URL? = nil,
        exportID: @escaping @Sendable () -> String = { UUID().uuidString },
        generatedAt: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) },
        archiveRunner: @escaping (String, [String]) async -> RuntimeCommandResult = ProcessRunner.run
    ) {
        self.fileManager = fileManager
        self.logCollector = logCollector
        self.productLogsDirectory = productLogsDirectory
        self.supplementalLogItems = supplementalLogItems
        self.rotatedSupplementalSets = rotatedSupplementalSets
        self.temporaryDirectory = temporaryDirectory
        self.exportID = exportID
        self.generatedAt = generatedAt
        self.archiveRunner = archiveRunner
    }

    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        var exportIssues = RuntimeLogExportIssues()
        do {
            try logCollector.refreshLogCollection()
        } catch {
            exportIssues.collectionIssue = error.localizedDescription
        }

        let stagingRoot = (temporaryDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent("vitalserver-log-export-\(exportID())", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        var exportSucceeded = false
        defer {
            if !exportSucceeded {
                try? fileManager.removeItem(at: stagingRoot)
            }
        }

        let bundleRoot = stagingRoot.appendingPathComponent("vitalserver-logs", isDirectory: true)
        try pathInspector.copyLogDirectory(
            from: productLogsDirectory,
            to: bundleRoot
        )
        try pathInspector.ensureBundleRootDirectory(bundleRoot)
        try stagingPermissionWriter.makeBundleWritable(bundleRoot)
        try copySupplementalLogs(to: bundleRoot, issues: &exportIssues)
        try writeExportManifest(to: bundleRoot, issues: exportIssues)

        let temporaryArchive = stagingRoot.appendingPathComponent(destination.lastPathComponent)
        let result = await archiveRunner(
            RuntimeControlClientConstants.Commands.ditto,
            ["-c", "-k", "--sequesterRsrc", "--keepParent", bundleRoot.path, temporaryArchive.path]
        )
        guard result.exitCode == 0 else {
            throw RuntimeClientError.logExportFailed(result.localSummary)
        }
        try pathInspector.moveArchiveReplacingFile(from: temporaryArchive, to: destination)
        exportSucceeded = true
        return RuntimeLogExportResult(
            destination: destination,
            cleanupIssue: cleanupStagingRoot(stagingRoot)
        )
    }

    private func cleanupStagingRoot(_ stagingRoot: URL) -> String? {
        do {
            try fileManager.removeItem(at: stagingRoot)
            return nil
        } catch {
            return "staging cleanup failed path=\(stagingRoot.path) reason=\(error.localizedDescription)"
        }
    }

    private func copySupplementalLogs(to bundleRoot: URL, issues: inout RuntimeLogExportIssues) throws {
        for item in supplementalLogItems {
            try copySupplementalLog(item, to: bundleRoot, issues: &issues)
        }
        for set in rotatedSupplementalSets {
            copyRotatedSupplementalLogs(set, to: bundleRoot, issues: &issues)
        }
    }

    private func copySupplementalLog(
        _ item: RuntimeLogExportSupplementalSource,
        to bundleRoot: URL,
        issues: inout RuntimeLogExportIssues
    ) throws {
        switch pathInspector.pathState(at: item.source) {
        case .file, .directory:
            break
        case .missing:
            return
        case .inspectFailed(let reason):
            issues.supplementalIssues[item.relativeDestination] = "source inspection failed: \(reason)"
            return
        case .other(let state), .unknown(let state):
            issues.supplementalIssues[item.relativeDestination] = "unexpected source path state: \(state)"
            return
        }
        let destination = bundleRoot.appendingPathComponent(item.relativeDestination)
        switch pathInspector.pathState(at: destination) {
        case .missing:
            break
        case .file, .directory, .other:
            return
        case .inspectFailed(let reason):
            issues.supplementalIssues[item.relativeDestination] = "destination inspection failed: \(reason)"
            return
        case .unknown(let state):
            issues.supplementalIssues[item.relativeDestination] = "unexpected destination path state: \(state)"
            return
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try fileManager.copyItem(at: item.source, to: destination)
        } catch {
            issues.supplementalIssues[item.relativeDestination] = error.localizedDescription
        }
    }

    private func copyRotatedSupplementalLogs(
        _ set: RuntimeLogExportRotatedSupplementalSet,
        to bundleRoot: URL,
        issues: inout RuntimeLogExportIssues
    ) {
        let issueKey = set.manifestKey
        let sourceDirectoryState = pathInspector.pathState(at: set.sourceDirectory)
        switch sourceDirectoryState {
        case .directory:
            break
        case .missing:
            return
        case .inspectFailed(let reason):
            issues.rotatedIssues[issueKey] = "source inspection failed: \(reason)"
            return
        case .file, .other, .unknown:
            issues.rotatedIssues[issueKey] = "unexpected source path state: \(sourceDirectoryState.rawValue)"
            return
        }
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: set.sourceDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            issues.rotatedIssues[issueKey] = error.localizedDescription
            return
        }
        for source in entries where source.lastPathComponent.hasPrefix(set.sourceFilePrefix) {
            let suffix = String(source.lastPathComponent.dropFirst(set.sourceFilePrefix.count))
            guard !suffix.isEmpty else {
                continue
            }
            let destination = bundleRoot
                .appendingPathComponent(set.relativeDestinationDirectory)
                .appendingPathComponent("\(set.destinationFilePrefix)\(suffix)")
            switch pathInspector.pathState(at: destination) {
            case .missing:
                break
            case .file, .directory, .other:
                continue
            case .inspectFailed(let reason):
                issues.rotatedIssues[issueKey] = "destination inspection failed: \(reason)"
                continue
            case .unknown(let state):
                issues.rotatedIssues[issueKey] = "unexpected destination path state: \(state)"
                continue
            }
            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: source, to: destination)
                issues.rotatedCopiedCounts[issueKey, default: 0] += 1
            } catch {
                issues.rotatedIssues[issueKey] = error.localizedDescription
            }
        }
    }

    private func writeExportManifest(to bundleRoot: URL, issues: RuntimeLogExportIssues) throws {
        let manifest = RuntimeLogExportManifest(
            generatedAt: generatedAt(),
            productLogsDirectory: productLogsDirectory.path,
            collectionIssue: issues.collectionIssue,
            supplementalItems: supplementalLogItems.map { item in
                let includedState = pathInspector.pathState(at: bundleRoot.appendingPathComponent(item.relativeDestination))
                let sourceState = pathInspector.pathState(at: item.source)
                let included = includedState.isPresent
                let sourcePresent = sourceState.isPresent
                let error = issues.supplementalIssues[item.relativeDestination]
                return RuntimeLogExportManifest.SupplementalItem(
                    source: item.source.path,
                    relativeDestination: item.relativeDestination,
                    sourcePathState: sourceState.rawValue,
                    sourcePresent: sourcePresent,
                    included: included,
                    status: RuntimeLogExportManifest.SupplementalItem.statusValue(
                        sourcePresent: sourcePresent,
                        included: included,
                        error: error
                    ),
                    error: error
                )
            },
            rotatedSupplementalSets: rotatedSupplementalSets.map { set in
                let sourceState = pathInspector.pathState(at: set.sourceDirectory)
                let copiedCount = issues.rotatedCopiedCounts[set.manifestKey] ?? 0
                let error = issues.rotatedIssues[set.manifestKey]
                return RuntimeLogExportManifest.RotatedSupplementalSet(
                    sourceDirectory: set.sourceDirectory.path,
                    sourceFilePrefix: set.sourceFilePrefix,
                    relativeDestinationDirectory: set.relativeDestinationDirectory,
                    destinationFilePrefix: set.destinationFilePrefix,
                    sourcePathState: sourceState.rawValue,
                    copiedCount: copiedCount,
                    status: RuntimeLogExportManifest.RotatedSupplementalSet.statusValue(
                        sourcePresent: sourceState.isPresent,
                        copiedCount: copiedCount,
                        error: error
                    ),
                    error: error
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
