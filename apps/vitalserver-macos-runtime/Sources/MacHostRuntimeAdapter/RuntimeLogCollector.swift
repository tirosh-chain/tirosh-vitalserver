import Foundation
import RuntimeControl
import Core
import Contracts
import HostInfrastructure

protocol RuntimeLogCollecting: Sendable {
    func refreshLogCollection() throws
    func refreshLogCollection(sourceID: RuntimeLogSource) throws
}

extension RuntimeLogCollecting {
    func refreshLogCollection(sourceID: RuntimeLogSource) throws {
        try refreshLogCollection()
    }
}

struct MacHostRuntimeLogCollector: RuntimeLogCollecting, @unchecked Sendable {
    private static let appendValidationByteLimit: UInt64 = 64 * 1024
    private static let appendChunkByteLimit = 256 * 1024

    private let fileStore: RuntimeFileStore
    private let copies: [RuntimeLogCopy]
    private let rotatedCopySets: [RuntimeRotatedLogCopySet]
    private let archiveDirectory: URL
    private let maxCentralLogBytes: UInt64
    private let calendar: Calendar
    private let now: () -> Date

    init(
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        copies: [RuntimeLogCopy] = RuntimeLogCopy.defaultCopies(),
        rotatedCopySets: [RuntimeRotatedLogCopySet] = RuntimeRotatedLogCopySet.defaultSets(),
        archiveDirectory: URL = URL(fileURLWithPath: RuntimeAdapterConstants.Paths.logArchive),
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

    func refreshLogCollection() throws {
        for item in copies {
            try copyIntoCentralLogs(item)
        }
        for set in rotatedCopySets {
            try copyRotatedLogs(set)
        }
    }

    func refreshLogCollection(sourceID: RuntimeLogSource) throws {
        guard sourceID != .helperMessage else {
            return
        }
        for item in copies where shouldRefresh(item, for: sourceID) {
            try copyIntoCentralLogs(item)
        }
        guard sourceID == .containers else {
            return
        }
        for set in rotatedCopySets {
            try copyRotatedLogs(set)
        }
    }

    private func copyIntoCentralLogs(_ item: RuntimeLogCopy) throws {
        guard fileStore.fileExists(item.source),
              try shouldRefreshCopy(from: item.source, to: item.destination)
        else {
            return
        }
        try fileStore.createDirectory(
            at: item.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileStore.fileExists(item.destination), try shouldRotateCentralLog(item.destination) {
            try archiveCentralLog(item.destination, prefix: item.archivePrefix)
        } else if try canAppendCopy(from: item.source, to: item.destination) {
            try appendNewLogBytes(from: item.source, to: item.destination)
            try touch(item.destination)
            return
        } else if fileStore.fileExists(item.destination) {
            try fileStore.removeItem(at: item.destination)
        }
        try fileStore.copyItem(at: item.source, to: item.destination)
        try touch(item.destination)
    }

    private func copyRotatedLogs(_ set: RuntimeRotatedLogCopySet) throws {
        guard fileStore.directoryExists(set.sourceDirectory) else {
            return
        }
        let entries = try fileStore.contentsOfDirectory(
            at: set.sourceDirectory,
            skipsHiddenFiles: true
        )

        for source in entries where source.lastPathComponent.hasPrefix(set.sourceFilePrefix) {
            let suffix = String(source.lastPathComponent.dropFirst(set.sourceFilePrefix.count))
            guard !suffix.isEmpty else {
                continue
            }
            let destination = set.destinationDirectory
                .appendingPathComponent("\(set.destinationFilePrefix)\(suffix)")
            try copyIntoCentralLogs(
                RuntimeLogCopy(
                    source: source,
                    destination: destination,
                    archivePrefix: "\(set.archivePrefix)\(suffix)"
                )
            )
        }
    }

    private func shouldRefreshCopy(from source: URL, to destination: URL) throws -> Bool {
        guard fileStore.fileExists(destination) else {
            return true
        }
        if try shouldRotateCentralLog(destination) {
            return true
        }
        let sourceSize = try fileStore.fileSize(source)
        let destinationSize = try fileStore.fileSize(destination)
        if sourceSize != destinationSize {
            return true
        }
        let sourceDate = try fileStore.modificationDate(source)
        let destinationDate = try fileStore.modificationDate(destination)
        return sourceDate > destinationDate
    }

    private func shouldRotateCentralLog(_ url: URL) throws -> Bool {
        guard fileStore.fileExists(url) else {
            return false
        }
        if try fileStore.fileSize(url) >= maxCentralLogBytes {
            return true
        }
        let date = try fileStore.modificationDate(url)
        return !calendar.isDateInToday(date)
    }

    private func archiveCentralLog(_ url: URL, prefix: String) throws {
        let date = try fileStore.modificationDate(url)
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

    private func shouldRefresh(_ item: RuntimeLogCopy, for sourceID: RuntimeLogSource) -> Bool {
        switch sourceID {
        case .helperMessage:
            return false
        case .install:
            return item.destination.path == RuntimeAdapterConstants.Paths.installLog
        case .command:
            return item.destination.path == RuntimeAdapterConstants.Paths.commandLog
        case .launcher:
            return item.destination.lastPathComponent == "launcher.log"
        case .vmLaunchOutput:
            return item.destination.lastPathComponent == "launchd.out.log"
        case .vmLaunchError:
            return item.destination.lastPathComponent == "launchd.err.log"
        case .proxyOutput:
            return item.destination.lastPathComponent == "proxy.out.log"
        case .proxyError:
            return item.destination.lastPathComponent == "proxy.err.log"
        case .watchdog:
            return item.destination.lastPathComponent == "watchdog.out.log"
        case .updateActivation:
            return item.destination.path == RuntimeAdapterConstants.Paths.updateActivationLog
        case .updateShutdown:
            return item.destination.path == RuntimeAdapterConstants.Paths.updateShutdownLog
        case .containers:
            return item.destination.path == RuntimeAdapterConstants.Paths.containerLogs
        }
    }

    private func canAppendCopy(from source: URL, to destination: URL) throws -> Bool {
        guard fileStore.fileExists(destination) else {
            return false
        }
        let sourceSize = try fileStore.fileSize(source)
        let destinationSize = try fileStore.fileSize(destination)
        guard sourceSize > destinationSize else {
            return false
        }
        return try sourceMatchesDestinationTail(
            source: source,
            destination: destination,
            destinationSize: destinationSize
        )
    }

    private func sourceMatchesDestinationTail(
        source: URL,
        destination: URL,
        destinationSize: UInt64
    ) throws -> Bool {
        let length = min(destinationSize, Self.appendValidationByteLimit)
        let offset = destinationSize - length
        guard let sourceData = try readData(source, offset: offset, length: length),
              let destinationData = try readData(destination, offset: offset, length: length)
        else {
            return false
        }
        return sourceData == destinationData
    }

    private func readData(_ url: URL, offset: UInt64, length: UInt64) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: Int(length))
    }

    private func appendNewLogBytes(from source: URL, to destination: URL) throws {
        let offset = try fileStore.fileSize(destination)
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer {
            try? sourceHandle.close()
        }
        try sourceHandle.seek(toOffset: offset)
        guard let data = try sourceHandle.read(upToCount: Self.appendChunkByteLimit), !data.isEmpty else {
            return
        }

        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer {
            try? destinationHandle.close()
        }
        try destinationHandle.seekToEnd()
        try destinationHandle.write(contentsOf: data)
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: now()],
            ofItemAtPath: url.path
        )
    }

}

struct RuntimeLogCopy {
    let source: URL
    let destination: URL
    let archivePrefix: String

    init(source: URL, destination: URL, archivePrefix: String) {
        self.source = source
        self.destination = destination
        self.archivePrefix = archivePrefix
    }

    static func defaultCopies() -> [RuntimeLogCopy] {
        let runtimeFiles = [
            "launcher.log",
            "launchd.out.log",
            "launchd.err.log",
            "proxy.out.log",
            "proxy.err.log",
            "guest-log-sync.out.log",
            "guest-log-sync.err.log",
            "sleep-prevention.out.log",
            "sleep-prevention.err.log",
            "watchdog.out.log",
            "watchdog.err.log",
        ].map { fileName in
            RuntimeLogCopy(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeLogSources)
                    .appendingPathComponent(fileName),
                destination: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.runtimeLogs)
                    .appendingPathComponent(fileName),
                archivePrefix: "runtime-\(fileName)"
            )
        }

        let guestFiles = [
            RuntimeLogCopy(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.bootstrapLogSource),
                destination: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.bootstrapLog),
                archivePrefix: "guest-bootstrap.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.containerLogSource),
                destination: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.containerLogs),
                archivePrefix: "guest-container-logs.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.updateActivationLogSource),
                destination: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.updateActivationLog),
                archivePrefix: "guest-activate-update.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.updateShutdownLogSource),
                destination: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.updateShutdownLog),
                archivePrefix: "guest-prepare-update-shutdown.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.datastoreRepairLogSource),
                destination: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.datastoreRepairLog),
                archivePrefix: "guest-repair-datastore.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.redisBackupLogSource),
                destination: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.redisBackupLog),
                archivePrefix: "guest-redis-backup.log"
            ),
            RuntimeLogCopy(
                source: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.commandLogFile),
                destination: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.commandLog),
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

    init(
        sourceDirectory: URL,
        sourceFilePrefix: String,
        destinationDirectory: URL,
        destinationFilePrefix: String,
        archivePrefix: String
    ) {
        self.sourceDirectory = sourceDirectory
        self.sourceFilePrefix = sourceFilePrefix
        self.destinationDirectory = destinationDirectory
        self.destinationFilePrefix = destinationFilePrefix
        self.archivePrefix = archivePrefix
    }

    static func defaultSets() -> [RuntimeRotatedLogCopySet] {
        [
            RuntimeRotatedLogCopySet(
                sourceDirectory: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.guestRunDirectory),
                sourceFilePrefix: "container-logs.log.",
                destinationDirectory: URL(fileURLWithPath: RuntimeAdapterConstants.Paths.guestLogs),
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
