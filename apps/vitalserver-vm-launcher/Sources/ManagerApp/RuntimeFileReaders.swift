import Foundation
import RuntimeCore
import RuntimeInfrastructure

protocol RuntimeManagerFileReading {
    func updateBundleSummary(url: URL) -> String
    func backups(latestBackupPath: String?) -> [RuntimeBackup]
    func logText(sourceID: String, helperMessage: String, lineLimit: Int) -> String
    func preferredLogsPath() -> String
    func vitalFileFolders(root: String) -> [VitalFileFolder]
}

struct SystemRuntimeManagerFileReader: RuntimeManagerFileReading {
    private let fileStore: RuntimeFileStore
    private let maxCentralLogBytes: UInt64 = 10 * 1024 * 1024

    init(fileStore: RuntimeFileStore = LocalRuntimeFileStore()) {
        self.fileStore = fileStore
    }

    func updateBundleSummary(url: URL) -> String {
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

    func logText(sourceID: String, helperMessage: String, lineLimit: Int) -> String {
        guard let sourceID = LogSourceID(rawValue: sourceID) else {
            return AppConstants.StatusText.noLogData
        }
        syncCentralLogCopies()
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
        syncCentralLogCopies()
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

    private func syncCentralLogCopies() {
        let runtimeFiles = [
            "launcher.log",
            "launchd.out.log",
            "launchd.err.log",
            "proxy.out.log",
            "proxy.err.log",
            "watchdog.out.log",
            "watchdog.err.log",
        ].map { fileName in
            CentralLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.runtimeLogSources)
                    .appendingPathComponent(fileName),
                destination: URL(fileURLWithPath: AppConstants.Paths.runtimeLogs)
                    .appendingPathComponent(fileName),
                archivePrefix: "runtime-\(fileName)"
            )
        }

        let guestFiles = [
            CentralLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.bootstrapLogSource),
                destination: URL(fileURLWithPath: AppConstants.Paths.bootstrapLog),
                archivePrefix: "guest-bootstrap.log"
            ),
            CentralLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.containerLogSource),
                destination: URL(fileURLWithPath: AppConstants.Paths.containerLogs),
                archivePrefix: "guest-container-logs.log"
            ),
            CentralLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.updateActivationLogSource),
                destination: URL(fileURLWithPath: AppConstants.Paths.updateActivationLog),
                archivePrefix: "guest-activate-update.log"
            ),
            CentralLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.datastoreRepairLogSource),
                destination: URL(fileURLWithPath: AppConstants.Paths.datastoreRepairLog),
                archivePrefix: "guest-repair-datastore.log"
            ),
            CentralLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.commandLogFile),
                destination: URL(fileURLWithPath: AppConstants.Paths.commandLog),
                archivePrefix: "command.log"
            ),
        ]

        for item in runtimeFiles + guestFiles {
            copyIntoCentralLogs(item)
        }
    }

    private func copyIntoCentralLogs(_ item: CentralLogCopy) {
        guard fileStore.fileExists(item.source),
              shouldRefreshCopy(from: item.source, to: item.destination)
        else {
            return
        }
        do {
            try fileStore.createDirectory(
                at: item.destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileStore.fileExists(item.destination), shouldRotateCentralLog(item.destination) {
                try archiveCentralLog(item.destination, prefix: item.archivePrefix)
            } else if fileStore.fileExists(item.destination) {
                try fileStore.removeItem(at: item.destination)
            }
            try fileStore.copyItem(at: item.source, to: item.destination)
            try FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: item.destination.path
            )
        } catch {
            return
        }
    }

    private func shouldRefreshCopy(from source: URL, to destination: URL) -> Bool {
        guard fileStore.fileExists(destination) else {
            return true
        }
        if shouldRotateCentralLog(destination) {
            return true
        }
        let sourceSize = (try? fileStore.fileSize(source)) ?? 0
        let destinationSize = (try? fileStore.fileSize(destination)) ?? 0
        if sourceSize != destinationSize {
            return true
        }
        guard let sourceDate = modificationDate(source),
              let destinationDate = modificationDate(destination) else {
            return true
        }
        return sourceDate > destinationDate
    }

    private func shouldRotateCentralLog(_ url: URL) -> Bool {
        guard fileStore.fileExists(url) else {
            return false
        }
        if ((try? fileStore.fileSize(url)) ?? 0) >= maxCentralLogBytes {
            return true
        }
        guard let date = modificationDate(url) else {
            return false
        }
        return !Calendar.current.isDateInToday(date)
    }

    private func archiveCentralLog(_ url: URL, prefix: String) throws {
        let date = modificationDate(url) ?? Date()
        let day = archiveDayFormatter.string(from: date)
        let timestamp = archiveTimestampFormatter.string(from: date)
        let archiveDirectory = URL(fileURLWithPath: AppConstants.Paths.logArchive)
            .appendingPathComponent(day, isDirectory: true)
        try fileStore.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let archiveName = "\(prefix).\(timestamp)"
        let destination = uniqueArchiveURL(
            archiveDirectory.appendingPathComponent(archiveName)
        )
        try fileStore.moveItem(at: url, to: destination)
    }

    private func uniqueArchiveURL(_ url: URL) -> URL {
        guard fileStore.fileExists(url) else {
            return url
        }
        for index in 1...999 {
            let candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).\(index)")
            if !fileStore.fileExists(candidate) {
                return candidate
            }
        }
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).\(UUID().uuidString)")
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func tail(_ content: String, lineLimit: Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(lineLimit).joined(separator: "\n")
    }
}

private struct CentralLogCopy {
    let source: URL
    let destination: URL
    let archivePrefix: String
}

private let archiveDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private let archiveTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
}()
