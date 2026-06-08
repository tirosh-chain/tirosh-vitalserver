import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

protocol RuntimeHostFileReading: Sendable {
    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult
    func backups(latestBackupPath: String?) throws -> [RuntimeBackup]
    func redisBackups() throws -> [RuntimeBackup]
    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) throws -> [VitalFilesFolder]
}

struct SystemRuntimeHostFileReader: RuntimeHostFileReading, @unchecked Sendable {
    private let fileStore: RuntimeFileStore
    private let logCollector: RuntimeLogCollecting
    private let logTextReader: RuntimeLogFileTextReader
    private let logSourceReadStrategyCatalog = RuntimeLogSourceReadStrategyCatalog()

    init(
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        logCollector: RuntimeLogCollecting = MacRuntimeControlLogCollector()
    ) {
        self.fileStore = fileStore
        self.logCollector = logCollector
        self.logTextReader = RuntimeLogFileTextReader(fileStore: fileStore)
    }

    func updateBundleSummaryResult(url: URL) -> RuntimeHostTextReadResult {
        if url.lastPathComponent.hasSuffix(".tar.gz") || url.lastPathComponent.hasSuffix(".tgz") {
            return .loaded("Archive: \(url.lastPathComponent)\nVerify to inspect manifest and checksums.")
        }
        let manifestURL = url.appendingPathComponent("manifest.json")
        let manifestState = fileStore.pathState(at: manifestURL)
        switch manifestState {
        case .file:
            break
        case .missing:
            return .missing(.message("Missing manifest.json"))
        case .inspectFailed(let reason):
            return .failed("Manifest path inspection failed: \(manifestURL.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("Manifest path state is unexpected: \(manifestURL.path) state=\(manifestState.rawValue)")
        }
        let manifest: UpdateBundleManifest
        do {
            let data = try fileStore.readData(manifestURL)
            manifest = try JSONDecoder().decode(UpdateBundleManifest.self, from: data)
        } catch {
            return .failed("Invalid manifest.json: \(error.localizedDescription)")
        }
        let artifacts = manifest.artifacts
            .map { artifact in "\(artifact.type.rawValue): \(artifact.name)" }
            .joined(separator: "\n")
        return .loaded("Version: \(manifest.version)\nArtifacts:\n\(artifacts)")
    }

    func backups(latestBackupPath: String?) throws -> [RuntimeBackup] {
        try RuntimeBackup.loadAll(latestBackupPath: latestBackupPath, fileStore: fileStore)
    }

    func redisBackups() throws -> [RuntimeBackup] {
        try RuntimeBackup.loadRedisBackups(fileStore: fileStore)
    }

    func logTextResult(sourceID: RuntimeLogSource, lineLimit: Int) -> RuntimeHostTextReadResult {
        let strategy = logSourceReadStrategyCatalog.strategy(for: sourceID)
        switch strategy {
        case .direct(let source):
            return logTextReader.read(source, lineLimit: lineLimit)
        case .refreshThenRead(let source):
            let refreshIssue = refreshLogCollectionIssue(sourceID)
            let text = logTextReader.read(source, lineLimit: lineLimit)
            return text.preservingRefreshIssue(refreshIssue)
        case .refreshWhenPrimaryMissing(let source):
            if logTextReader.primaryFileIsMissing(source) {
                let refreshIssue = refreshLogCollectionIssue(sourceID)
                let text = logTextReader.read(source, lineLimit: lineLimit)
                return text.preservingRefreshIssue(refreshIssue)
            }
            return logTextReader.read(source, lineLimit: lineLimit)
        }
    }

    private func refreshLogCollectionIssue(_ sourceID: RuntimeLogSource) -> String? {
        do {
            try logCollector.refreshLogCollection(sourceID: sourceID)
            return nil
        } catch {
            return "Failed to refresh log collection: \(error.localizedDescription)"
        }
    }

    func preferredLogsPath() -> String {
        return RuntimeControlClientConstants.Paths.productLogs
    }

    func vitalFileFolders(root: String) throws -> [VitalFilesFolder] {
        let rootURL = URL(fileURLWithPath: root)
        let entries = try fileStore.contentsOfDirectory(at: rootURL, skipsHiddenFiles: false)
        var directories: [URL] = []
        for entry in entries {
            let state = fileStore.pathState(at: entry)
            switch state {
            case .directory:
                directories.append(entry)
            case .file, .missing:
                continue
            case .inspectFailed(let reason):
                throw RuntimeHostFileReaderError.pathInspectionFailed(path: entry.path, reason: reason)
            case .other, .unknown:
                throw RuntimeHostFileReaderError.unexpectedPathState(path: entry.path, state: state.rawValue)
            }
        }
        return directories
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { item in VitalFilesFolder(name: item.lastPathComponent, path: item.path) }
    }

}

private extension RuntimeHostTextReadResult {
    func preservingRefreshIssue(_ issue: String?) -> RuntimeHostTextReadResult {
        guard let issue else {
            return self
        }
        switch self {
        case .loaded(let text):
            return .loadedWithIssue(text: text, issue: issue)
        case .loadedWithIssue(let text, let existingIssue):
            return .loadedWithIssue(text: text, issue: "\(issue)\n\(existingIssue)")
        case .missing:
            return .failed(issue)
        case .failed(let message):
            return .failed("\(issue)\n\(message)")
        }
    }
}
