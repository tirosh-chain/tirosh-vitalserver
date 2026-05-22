import Foundation
import RuntimeCore
import RuntimeInfrastructure

protocol RuntimeLogCollecting {
    func refreshLogCollection()
}

struct LocalRuntimeLogCollector: RuntimeLogCollecting {
    private let fileStore: RuntimeFileStore
    private let copies: [RuntimeLogCopy]
    private let rotatedCopySets: [RuntimeRotatedLogCopySet]
    private let archiveDirectory: URL
    private let maxCentralLogBytes: UInt64
    private let calendar: Calendar
    private let now: () -> Date

    init(
        fileStore: RuntimeFileStore = LocalRuntimeFileStore(),
        copies: [RuntimeLogCopy] = RuntimeLogCopy.defaultCopies(),
        rotatedCopySets: [RuntimeRotatedLogCopySet] = RuntimeRotatedLogCopySet.defaultSets(),
        archiveDirectory: URL = URL(fileURLWithPath: AppConstants.Paths.logArchive),
        maxCentralLogBytes: UInt64 = 10 * 1024 * 1024,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileStore = fileStore
        self.copies = copies
        self.rotatedCopySets = rotatedCopySets
        self.archiveDirectory = archiveDirectory
        self.maxCentralLogBytes = maxCentralLogBytes
        self.calendar = calendar
        self.now = now
    }

    func refreshLogCollection() {
        for item in copies {
            copyIntoCentralLogs(item)
        }
        for set in rotatedCopySets {
            copyRotatedLogs(set)
        }
    }

    private func copyIntoCentralLogs(_ item: RuntimeLogCopy) {
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
                [.modificationDate: now()],
                ofItemAtPath: item.destination.path
            )
        } catch {
            return
        }
    }

    private func copyRotatedLogs(_ set: RuntimeRotatedLogCopySet) {
        guard let entries = try? fileStore.contentsOfDirectory(
            at: set.sourceDirectory,
            skipsHiddenFiles: true
        ) else {
            return
        }

        for source in entries where source.lastPathComponent.hasPrefix(set.sourceFilePrefix) {
            let suffix = String(source.lastPathComponent.dropFirst(set.sourceFilePrefix.count))
            guard !suffix.isEmpty else {
                continue
            }
            let destination = set.destinationDirectory
                .appendingPathComponent("\(set.destinationFilePrefix)\(suffix)")
            copyIntoCentralLogs(
                RuntimeLogCopy(
                    source: source,
                    destination: destination,
                    archivePrefix: "\(set.archivePrefix)\(suffix)"
                )
            )
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
        return !calendar.isDateInToday(date)
    }

    private func archiveCentralLog(_ url: URL, prefix: String) throws {
        let date = modificationDate(url) ?? now()
        let day = archiveDayFormatter.string(from: date)
        let timestamp = archiveTimestampFormatter.string(from: date)
        let dayArchiveDirectory = archiveDirectory.appendingPathComponent(day, isDirectory: true)
        try fileStore.createDirectory(at: dayArchiveDirectory, withIntermediateDirectories: true)
        let archiveName = "\(prefix).\(timestamp)"
        let destination = uniqueArchiveURL(
            dayArchiveDirectory.appendingPathComponent(archiveName)
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
}

struct RuntimeLogCopy {
    let source: URL
    let destination: URL
    let archivePrefix: String

    static func defaultCopies() -> [RuntimeLogCopy] {
        let runtimeFiles = [
            "launcher.log",
            "launchd.out.log",
            "launchd.err.log",
            "proxy.out.log",
            "proxy.err.log",
            "watchdog.out.log",
            "watchdog.err.log",
        ].map { fileName in
            RuntimeLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.runtimeLogSources)
                    .appendingPathComponent(fileName),
                destination: URL(fileURLWithPath: AppConstants.Paths.runtimeLogs)
                    .appendingPathComponent(fileName),
                archivePrefix: "runtime-\(fileName)"
            )
        }

        let guestFiles = [
            RuntimeLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.bootstrapLogSource),
                destination: URL(fileURLWithPath: AppConstants.Paths.bootstrapLog),
                archivePrefix: "guest-bootstrap.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.containerLogSource),
                destination: URL(fileURLWithPath: AppConstants.Paths.containerLogs),
                archivePrefix: "guest-container-logs.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.updateActivationLogSource),
                destination: URL(fileURLWithPath: AppConstants.Paths.updateActivationLog),
                archivePrefix: "guest-activate-update.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.datastoreRepairLogSource),
                destination: URL(fileURLWithPath: AppConstants.Paths.datastoreRepairLog),
                archivePrefix: "guest-repair-datastore.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: AppConstants.Paths.commandLogFile),
                destination: URL(fileURLWithPath: AppConstants.Paths.commandLog),
                archivePrefix: "command.log"
            ),
        ]

        return runtimeFiles + guestFiles
    }
}

struct RuntimeRotatedLogCopySet {
    let sourceDirectory: URL
    let sourceFilePrefix: String
    let destinationDirectory: URL
    let destinationFilePrefix: String
    let archivePrefix: String

    static func defaultSets() -> [RuntimeRotatedLogCopySet] {
        [
            RuntimeRotatedLogCopySet(
                sourceDirectory: URL(fileURLWithPath: AppConstants.Paths.guestRunDirectory),
                sourceFilePrefix: "container-logs.log.",
                destinationDirectory: URL(fileURLWithPath: AppConstants.Paths.guestLogs),
                destinationFilePrefix: "container-logs.log.",
                archivePrefix: "guest-container-logs.log."
            ),
        ]
    }
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
