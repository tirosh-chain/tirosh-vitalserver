import Foundation
import RuntimeCore
import HostRuntimeInfrastructure

protocol RuntimeManagerFileReading {
    func updateBundleSummary(url: URL) -> String
    func backups(latestBackupPath: String?) -> [RuntimeBackup]
    func logText(sourceID: LogSourceID, helperMessage: String, lineLimit: Int) -> String
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) -> [VitalFileFolder]
}

struct SystemRuntimeManagerFileReader: RuntimeManagerFileReading {
    private let fileStore: RuntimeFileStore
    private let logCollector: RuntimeLogCollecting

    init(
        fileStore: RuntimeFileStore = LocalRuntimeFileStore(),
        logCollector: RuntimeLogCollecting = LocalRuntimeLogCollector()
    ) {
        self.fileStore = fileStore
        self.logCollector = logCollector
    }

    func updateBundleSummary(url: URL) -> String {
        if url.lastPathComponent.hasSuffix(".tar.gz") || url.lastPathComponent.hasSuffix(".tgz") {
            return "Archive: \(url.lastPathComponent)\nVerify to inspect manifest and checksums."
        }
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? fileStore.readData(manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Missing or invalid manifest.json"
        }
        let version = object["version"] as? String ?? "unknown"
        let artifacts = (object["artifacts"] as? [[String: Any]] ?? [])
            .compactMap { artifact -> String? in
                guard let type = artifact["type"] as? String,
                      let name = artifact["name"] as? String else { return nil }
                return "\(type): \(name)"
            }
            .joined(separator: "\n")
        return "Version: \(version)\nArtifacts:\n\(artifacts)"
    }

    func backups(latestBackupPath: String?) -> [RuntimeBackup] {
        RuntimeBackup.loadAll(latestBackupPath: latestBackupPath, fileStore: fileStore)
    }

    func logText(sourceID: LogSourceID, helperMessage: String, lineLimit: Int) -> String {
        logCollector.refreshLogCollection()
        switch sourceID {
        case .helperMessage:
            return helperMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppConstants.StatusText.noLogData
                : helperMessage
        case .install:
            return logFile(path: AppConstants.Paths.installLog, lineLimit: lineLimit)
        case .command:
            return logFile(
                path: AppConstants.Paths.commandLog,
                lineLimit: lineLimit,
                fallbackPath: AppConstants.Paths.commandLogFile
            )
        case .launcher:
            return logFile(
                path: (AppConstants.Paths.runtimeLogs as NSString).appendingPathComponent("launcher.log"),
                lineLimit: lineLimit,
                fallbackPath: (AppConstants.Paths.runtimeLogSources as NSString).appendingPathComponent("launcher.log")
            )
        case .proxyOutput:
            return logFile(
                path: (AppConstants.Paths.runtimeLogs as NSString).appendingPathComponent("proxy.out.log"),
                lineLimit: lineLimit,
                fallbackPath: (AppConstants.Paths.runtimeLogSources as NSString).appendingPathComponent("proxy.out.log")
            )
        case .proxyError:
            return logFile(
                path: (AppConstants.Paths.runtimeLogs as NSString).appendingPathComponent("proxy.err.log"),
                lineLimit: lineLimit,
                fallbackPath: (AppConstants.Paths.runtimeLogSources as NSString).appendingPathComponent("proxy.err.log")
            )
        case .updateActivation:
            return logFile(
                path: AppConstants.Paths.updateActivationLog,
                lineLimit: lineLimit,
                fallbackPath: AppConstants.Paths.updateActivationLogSource
            )
        case .containers:
            return logFile(
                path: AppConstants.Paths.containerLogs,
                lineLimit: lineLimit,
                fallbackPath: AppConstants.Paths.containerLogSource
            )
        }
    }

    func preferredLogsPath() -> String {
        logCollector.refreshLogCollection()
        if fileStore.directoryExists(URL(fileURLWithPath: AppConstants.Paths.productLogs)) {
            return AppConstants.Paths.productLogs
        }
        return AppConstants.Paths.installLog
    }

    func vitalFileFolders(root: String) -> [VitalFileFolder] {
        let rootURL = URL(fileURLWithPath: root)
        guard let entries = try? fileStore.contentsOfDirectory(at: rootURL, skipsHiddenFiles: false) else {
            return []
        }
        return entries
            .filter { fileStore.directoryExists($0) }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map { item in
                VitalFileFolder(name: item.lastPathComponent, path: item.path)
            }
    }

    private func logFile(path: String, lineLimit: Int, fallbackPath: String? = nil) -> String {
        let url = URL(fileURLWithPath: path)
        let readableURL: URL
        if fileStore.fileExists(url) {
            readableURL = url
        } else if let fallbackPath {
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            guard fileStore.fileExists(fallbackURL) else {
                return AppConstants.StatusText.noLogData
            }
            readableURL = fallbackURL
        } else {
            return AppConstants.StatusText.noLogData
        }
        guard let content = try? fileStore.readUTF8Text(readableURL) else {
            return AppConstants.StatusText.noLogData
        }
        let body = tail(content, lineLimit: lineLimit)
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppConstants.StatusText.noLogData
            : body
    }

    private func tail(_ content: String, lineLimit: Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(lineLimit).joined(separator: "\n")
    }
}
