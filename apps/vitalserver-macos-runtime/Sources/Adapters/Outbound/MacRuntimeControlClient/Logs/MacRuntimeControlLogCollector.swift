import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

protocol RuntimeLogCollecting: Sendable {
    func refreshLogCollection() throws
    func refreshLogCollection(sourceID: RuntimeLogSource) throws
}

extension RuntimeLogCollecting {
    func refreshLogCollection(sourceID: RuntimeLogSource) throws {
        try refreshLogCollection()
    }
}

struct MacRuntimeControlLogCollector: RuntimeLogCollecting, @unchecked Sendable {
    private static let appendValidationByteLimit: UInt64 = 64 * 1024
    private static let appendChunkByteLimit = 256 * 1024

    private let fileStore: RuntimeFileStore
    private let copies: [RuntimeLogCopy]
    private let directoryCopies: [RuntimeLogDirectoryCopy]
    private let rotatedCopySets: [RuntimeRotatedLogCopySet]
    private let archiveDirectory: URL
    private let archiveRetention: RuntimeLogArchiveRetentionConfiguration?
    private let runtimeControlSettingsPath: URL
    private let maxCentralLogBytes: UInt64
    private let calendar: Calendar
    private let now: () -> Date
    private let archiveCollisionID: () -> String
    private let setModificationDate: (URL, Date) throws -> Void
    private let collectionRules: RuntimeLogCollectionDecisionRules
    private var pathInspector: RuntimeLogCollectionPathInspector {
        RuntimeLogCollectionPathInspector(fileStore: fileStore)
    }

    init(
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        copies: [RuntimeLogCopy] = RuntimeLogCopy.defaultCopies(),
        directoryCopies: [RuntimeLogDirectoryCopy] = RuntimeLogDirectoryCopy.defaultCopies(),
        rotatedCopySets: [RuntimeRotatedLogCopySet] = RuntimeRotatedLogCopySet.defaultSets(),
        archiveDirectory: URL = URL(fileURLWithPath: RuntimeControlClientConstants.Paths.logArchive),
        archiveRetention: RuntimeLogArchiveRetentionConfiguration? = nil,
        runtimeControlSettingsPath: URL = URL(fileURLWithPath: RuntimeControlClientConstants.Paths.runtimeControlSettings),
        maxCentralLogBytes: UInt64 = 10 * 1024 * 1024,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        archiveCollisionID: @escaping () -> String = { UUID().uuidString },
        setModificationDate: ((URL, Date) throws -> Void)? = nil
    ) {
        self.fileStore = fileStore
        self.copies = copies
        self.directoryCopies = directoryCopies
        self.rotatedCopySets = rotatedCopySets
        self.archiveDirectory = archiveDirectory
        self.archiveRetention = archiveRetention
        self.runtimeControlSettingsPath = runtimeControlSettingsPath
        self.maxCentralLogBytes = maxCentralLogBytes
        self.calendar = calendar
        self.now = now
        self.archiveCollisionID = archiveCollisionID
        self.collectionRules = RuntimeLogCollectionDecisionRules(calendar: calendar)
        if let setModificationDate {
            self.setModificationDate = setModificationDate
        } else if let metadataWriter = fileStore as? RuntimeFileMetadataWriting {
            self.setModificationDate = { url, date in
                try metadataWriter.setModificationDate(date, at: url)
            }
        } else {
            self.setModificationDate = { url, _ in
                throw RuntimeControlLogCollectorError.metadataWriteUnsupported(path: url.path)
            }
        }
    }

    func refreshLogCollection() throws {
        for item in copies {
            try copyIntoCentralLogs(item)
        }
        for item in directoryCopies {
            try copyDirectoryIntoCentralLogs(item)
        }
        for set in rotatedCopySets {
            try copyRotatedLogs(set)
        }
        try pruneLogArchives()
    }

    func refreshLogCollection(sourceID: RuntimeLogSource) throws {
        guard sourceID != .helperMessage else {
            return
        }
        for item in copies where collectionRules.shouldRefreshTarget(
            RuntimeLogCollectionRefreshTargetInput(
                sourceID: sourceID,
                destinationFileName: item.destination.lastPathComponent
            )
        ) {
            try copyIntoCentralLogs(item)
        }
        if sourceID == .containers {
            for item in directoryCopies {
                try copyDirectoryIntoCentralLogs(item)
            }
            for set in rotatedCopySets {
                try copyRotatedLogs(set)
            }
        }
        try pruneLogArchives()
    }

    private func pruneLogArchives() throws {
        try RuntimeLogArchivePruner(
            archiveDirectory: archiveDirectory,
            configuration: try effectiveArchiveRetention(),
            fileStore: fileStore,
            calendar: calendar,
            now: now
        ).prune()
    }

    private func effectiveArchiveRetention() throws -> RuntimeLogArchiveRetentionConfiguration {
        if let archiveRetention {
            return archiveRetention
        }
        switch RuntimeControlSettingsDocument.loadResult(
            path: runtimeControlSettingsPath.path,
            fileStore: fileStore
        ) {
        case .loaded(let input):
            return RuntimeLogArchiveRetentionConfiguration(
                retentionDays: input.retentionDays,
                maximumBytes: UInt64(input.maximumGiB) * 1_073_741_824
            )
        case .missing:
            return RuntimeLogArchiveRetentionConfiguration()
        case .failed(let reason):
            throw RuntimeControlLogCollectorError.archiveRetentionSettingsReadFailed(
                path: runtimeControlSettingsPath.path,
                reason: reason
            )
        }
    }

    private func copyDirectoryIntoCentralLogs(_ item: RuntimeLogDirectoryCopy) throws {
        guard try pathInspector.expectedDirectoryIsPresent(item.source) else {
            return
        }
        try fileStore.createDirectory(
            at: item.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if try pathInspector.pathIsPresent(item.destination) {
            try fileStore.removeItem(at: item.destination)
        }
        try fileStore.copyItem(at: item.source, to: item.destination)
    }

    private func copyIntoCentralLogs(_ item: RuntimeLogCopy) throws {
        guard try pathInspector.expectedLogFileIsPresent(item.source),
              try shouldRefreshCopy(from: item.source, to: item.destination)
        else {
            return
        }
        try fileStore.createDirectory(
            at: item.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if try pathInspector.expectedLogFileIsPresent(item.destination), try shouldRotateCentralLog(item.destination) {
            try archiveCentralLog(item.destination, prefix: item.archivePrefix)
        } else if try canAppendCopy(from: item.source, to: item.destination) {
            try appendNewLogBytes(from: item.source, to: item.destination)
            try touch(item.destination)
            return
        } else if try pathInspector.expectedLogFileIsPresent(item.destination) {
            try fileStore.removeItem(at: item.destination)
        }
        try fileStore.copyItem(at: item.source, to: item.destination)
        try touch(item.destination)
    }

    private func copyRotatedLogs(_ set: RuntimeRotatedLogCopySet) throws {
        guard try pathInspector.expectedDirectoryIsPresent(set.sourceDirectory) else {
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
        let destinationPresent = try pathInspector.expectedLogFileIsPresent(destination)
        guard destinationPresent else {
            let nowValue = now()
            return collectionRules.shouldRefreshCopy(
                RuntimeLogCollectionCopyRefreshInput(
                    destinationPresent: false,
                    rotationRequired: false,
                    sourceSize: 0,
                    destinationSize: 0,
                    sourceModificationDate: nowValue,
                    destinationModificationDate: nowValue
                )
            )
        }
        let rotationRequired = try shouldRotateCentralLog(destination)
        guard !rotationRequired else {
            let nowValue = now()
            return collectionRules.shouldRefreshCopy(
                RuntimeLogCollectionCopyRefreshInput(
                    destinationPresent: true,
                    rotationRequired: true,
                    sourceSize: 0,
                    destinationSize: 0,
                    sourceModificationDate: nowValue,
                    destinationModificationDate: nowValue
                )
            )
        }
        let sourceSize = try fileStore.fileSize(source)
        let sourceDate = try fileStore.modificationDate(source)
        let destinationSize = try fileStore.fileSize(destination)
        let destinationDate = try fileStore.modificationDate(destination)
        return collectionRules.shouldRefreshCopy(
            RuntimeLogCollectionCopyRefreshInput(
                destinationPresent: destinationPresent,
                rotationRequired: rotationRequired,
                sourceSize: sourceSize,
                destinationSize: destinationSize,
                sourceModificationDate: sourceDate,
                destinationModificationDate: destinationDate
            )
        )
    }

    private func shouldRotateCentralLog(_ url: URL) throws -> Bool {
        let destinationPresent = try pathInspector.expectedLogFileIsPresent(url)
        let nowValue = now()
        guard destinationPresent else {
            return collectionRules.shouldRotateCentralLog(
                RuntimeLogCollectionRotationInput(
                    destinationPresent: false,
                    fileSize: 0,
                    modificationDate: nowValue,
                    now: nowValue,
                    maxCentralLogBytes: maxCentralLogBytes
                )
            )
        }
        return collectionRules.shouldRotateCentralLog(
            RuntimeLogCollectionRotationInput(
                destinationPresent: destinationPresent,
                fileSize: try fileStore.fileSize(url),
                modificationDate: try fileStore.modificationDate(url),
                now: nowValue,
                maxCentralLogBytes: maxCentralLogBytes
            )
        )
    }

    private func archiveCentralLog(_ url: URL, prefix: String) throws {
        let date = try fileStore.modificationDate(url)
        let day = RuntimeLogArchiveNameFormatter.day(date)
        let timestamp = RuntimeLogArchiveNameFormatter.timestamp(date)
        let dayArchiveDirectory = archiveDirectory.appendingPathComponent(day, isDirectory: true)
        try fileStore.createDirectory(at: dayArchiveDirectory, withIntermediateDirectories: true)
        let archiveName = "\(prefix).\(timestamp)"
        let destination = try uniqueArchiveURL(
            dayArchiveDirectory.appendingPathComponent(archiveName)
        )
        try fileStore.moveItem(at: url, to: destination)
    }

    private func uniqueArchiveURL(_ url: URL) throws -> URL {
        guard try pathInspector.expectedLogFileIsPresent(url) else {
            return url
        }
        for index in 1...999 {
            let candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).\(index)")
            if try !pathInspector.expectedLogFileIsPresent(candidate) {
                return candidate
            }
        }
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).\(archiveCollisionID())")
    }

    private func canAppendCopy(from source: URL, to destination: URL) throws -> Bool {
        let destinationPresent = try pathInspector.expectedLogFileIsPresent(destination)
        let sourceSize = try fileStore.fileSize(source)
        let destinationSize = destinationPresent ? try fileStore.fileSize(destination) : 0
        let sourceMatchesDestinationTail = destinationPresent && sourceSize > destinationSize
            ? try sourceMatchesDestinationTail(
                source: source,
                destination: destination,
                destinationSize: destinationSize
            )
            : false
        return collectionRules.canAppendCopy(
            RuntimeLogCollectionAppendInput(
                destinationPresent: destinationPresent,
                sourceSize: sourceSize,
                destinationSize: destinationSize,
                sourceMatchesDestinationTail: sourceMatchesDestinationTail
            )
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
        let data = try readData(url, offset: offset)
        return Data(data.prefix(Int(length)))
    }

    private func appendNewLogBytes(from source: URL, to destination: URL) throws {
        let offset = try fileStore.fileSize(destination)
        let chunk = Data(try readData(source, offset: offset).prefix(Self.appendChunkByteLimit))
        guard !chunk.isEmpty else {
            return
        }
        try fileStore.writeData(try fileStore.readData(destination) + chunk, to: destination, options: [])
    }

    private func touch(_ url: URL) throws {
        try setModificationDate(url, now())
    }

    private func readData(_ url: URL, offset: UInt64) throws -> Data {
        if let partialReader = fileStore as? RuntimeFilePartialReading {
            return try partialReader.readData(url, offset: offset)
        }
        let data = try fileStore.readData(url)
        guard offset < UInt64(data.count) else {
            return Data()
        }
        return Data(data.dropFirst(Int(offset)))
    }

}
