import Foundation

@MainActor
protocol RuntimeLogExporting {
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult
}

@MainActor
struct LocalRuntimeLogExporter: RuntimeLogExporting {
    private let fileManager: FileManager
    private let logCollector: RuntimeLogCollecting

    init(
        fileManager: FileManager = .default,
        logCollector: RuntimeLogCollecting = LocalRuntimeLogCollector()
    ) {
        self.fileManager = fileManager
        self.logCollector = logCollector
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
            from: URL(fileURLWithPath: AppConstants.Paths.productLogs),
            to: bundleRoot
        )
        if !fileManager.fileExists(atPath: bundleRoot.path) {
            try fileManager.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        }

        let temporaryArchive = stagingRoot.appendingPathComponent(destination.lastPathComponent)
        let result = await ProcessRunner.run(
            AppConstants.Commands.ditto,
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", bundleRoot.path, temporaryArchive.path]
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
}
