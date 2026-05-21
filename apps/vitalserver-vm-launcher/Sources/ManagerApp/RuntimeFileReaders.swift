import Foundation

protocol RuntimeManagerFileReading {
    func updateBundleSummary(url: URL) -> String
    func backups(latestBackupPath: String?) -> [RuntimeBackup]
    func logText(sourceID: String, helperMessage: String, lineLimit: Int) -> String
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) -> [VitalFileFolder]
}

struct SystemRuntimeManagerFileReader: RuntimeManagerFileReading {
    func updateBundleSummary(url: URL) -> String {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = FileManager.default.contents(atPath: manifestURL.path),
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
        RuntimeBackup.loadAll(latestBackupPath: latestBackupPath)
    }

    func logText(sourceID: String, helperMessage: String, lineLimit: Int) -> String {
        guard let sourceID = LogSourceID(rawValue: sourceID) else {
            return AppConstants.StatusText.noLogData
        }
        switch sourceID {
        case .helperMessage:
            return helperMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppConstants.StatusText.noLogData
                : helperMessage
        case .install:
            return logFile(path: AppConstants.Paths.installLog, lineLimit: lineLimit)
        case .command:
            return logFile(path: AppConstants.Paths.commandLogFile, lineLimit: lineLimit)
        case .launcher:
            return logFile(
                path: (AppConstants.Paths.runtimeLogs as NSString).appendingPathComponent("launcher.log"),
                lineLimit: lineLimit
            )
        case .proxyOutput:
            return logFile(
                path: (AppConstants.Paths.runtimeLogs as NSString).appendingPathComponent("proxy.out.log"),
                lineLimit: lineLimit
            )
        case .proxyError:
            return logFile(
                path: (AppConstants.Paths.runtimeLogs as NSString).appendingPathComponent("proxy.err.log"),
                lineLimit: lineLimit
            )
        case .updateActivation:
            return logFile(path: AppConstants.Paths.updateActivationLog, lineLimit: lineLimit)
        case .containers:
            return logFile(path: AppConstants.Paths.containerLogs, lineLimit: lineLimit)
        }
    }

    func preferredLogsPath() -> String {
        if FileManager.default.fileExists(atPath: AppConstants.Paths.runtimeLogs) {
            return AppConstants.Paths.runtimeLogs
        }
        return AppConstants.Paths.installLog
    }

    func vitalFileFolders(root: String) -> [VitalFileFolder] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            return []
        }
        return entries
            .map { entry in
                (name: entry, path: (root as NSString).appendingPathComponent(entry))
            }
            .filter { item in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { item in
                VitalFileFolder(name: item.name, path: item.path)
            }
    }

    private func logFile(path: String, lineLimit: Int) -> String {
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
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
