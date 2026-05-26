import Foundation
import RuntimeControl
import Core
import Contracts
import HostInfrastructure

protocol RuntimeHostFileReading {
    func updateBundleSummary(url: URL) -> String
    func backups(latestBackupPath: String?) -> [RuntimeBackup]
    func logText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) -> String
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) -> [VitalFilesFolder]
}

struct SystemRuntimeHostFileReader: RuntimeHostFileReading {
    private static let logTailReadByteLimit: UInt64 = 512 * 1024

    private let fileStore: RuntimeFileStore
    private let logCollector: RuntimeLogCollecting

    init(
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        logCollector: RuntimeLogCollecting = MacHostRuntimeLogCollector()
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

    func logText(sourceID: RuntimeLogSource, helperMessage: String, lineLimit: Int) -> String {
        switch sourceID {
        case .helperMessage:
            return helperMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? RuntimeAdapterConstants.StatusText.noLogData
                : helperMessage
        default:
            logCollector.refreshLogCollection(sourceID: sourceID)
            return logFile(sourceID: sourceID, lineLimit: lineLimit)
        }
    }

    private func logFile(sourceID: RuntimeLogSource, lineLimit: Int) -> String {
        switch sourceID {
        case .helperMessage:
            return RuntimeAdapterConstants.StatusText.noLogData
        case .install:
            return logFile(path: RuntimeAdapterConstants.Paths.installLog, lineLimit: lineLimit)
        case .command:
            return logFile(
                path: RuntimeAdapterConstants.Paths.commandLog,
                lineLimit: lineLimit,
                fallbackPath: RuntimeAdapterConstants.Paths.commandLogFile
            )
        case .launcher:
            return logFile(
                path: (RuntimeAdapterConstants.Paths.runtimeLogs as NSString).appendingPathComponent("launcher.log"),
                lineLimit: lineLimit,
                fallbackPath: (RuntimeAdapterConstants.Paths.runtimeLogSources as NSString).appendingPathComponent("launcher.log")
            )
        case .proxyOutput:
            return logFile(
                path: (RuntimeAdapterConstants.Paths.runtimeLogs as NSString).appendingPathComponent("proxy.out.log"),
                lineLimit: lineLimit,
                fallbackPath: (RuntimeAdapterConstants.Paths.runtimeLogSources as NSString).appendingPathComponent("proxy.out.log")
            )
        case .proxyError:
            return logFile(
                path: (RuntimeAdapterConstants.Paths.runtimeLogs as NSString).appendingPathComponent("proxy.err.log"),
                lineLimit: lineLimit,
                fallbackPath: (RuntimeAdapterConstants.Paths.runtimeLogSources as NSString).appendingPathComponent("proxy.err.log")
            )
        case .updateActivation:
            return logFile(
                path: RuntimeAdapterConstants.Paths.updateActivationLog,
                lineLimit: lineLimit,
                fallbackPath: RuntimeAdapterConstants.Paths.updateActivationLogSource
            )
        case .containers:
            return logFile(
                path: RuntimeAdapterConstants.Paths.containerLogs,
                lineLimit: lineLimit,
                fallbackPath: RuntimeAdapterConstants.Paths.containerLogSource
            )
        }
    }

    func preferredLogsPath() -> String {
        logCollector.refreshLogCollection()
        if fileStore.directoryExists(URL(fileURLWithPath: RuntimeAdapterConstants.Paths.productLogs)) {
            return RuntimeAdapterConstants.Paths.productLogs
        }
        return RuntimeAdapterConstants.Paths.installLog
    }

    func vitalFileFolders(root: String) -> [VitalFilesFolder] {
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
                VitalFilesFolder(name: item.lastPathComponent, path: item.path)
            }
    }

    private func logFile(path: String, lineLimit: Int, fallbackPath: String? = nil) -> String {
        let url = URL(fileURLWithPath: path)
        let readableURL: URL
        if fileStore.fileExists(url) {
            readableURL = url
        } else if let fallbackPath {
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            if fileStore.fileExists(fallbackURL) {
                readableURL = fallbackURL
            } else {
                return RuntimeAdapterConstants.StatusText.noLogData
            }
        } else {
            return RuntimeAdapterConstants.StatusText.noLogData
        }
        guard let content = readTailText(readableURL) else {
            return RuntimeAdapterConstants.StatusText.noLogData
        }
        let body = tail(content, lineLimit: lineLimit)
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RuntimeAdapterConstants.StatusText.noLogData
            : body
    }

    private func tail(_ content: String, lineLimit: Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(lineLimit).joined(separator: "\n")
    }

    private func readTailText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        let fileSize = (try? fileStore.fileSize(url)) ?? 0
        if fileSize > Self.logTailReadByteLimit {
            try? handle.seek(toOffset: fileSize - Self.logTailReadByteLimit)
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
