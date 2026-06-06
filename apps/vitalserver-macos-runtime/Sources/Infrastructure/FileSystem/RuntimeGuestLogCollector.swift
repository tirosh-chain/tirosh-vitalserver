import Application
import Foundation

public struct RuntimeGuestLogCollector {
    private static let appendValidationByteLimit: UInt64 = 64 * 1024

    private let installedPaths: InstalledRuntimePaths
    private let fileStore: RuntimeFileStore

    public init(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStore
    ) {
        self.installedPaths = installedPaths
        self.fileStore = fileStore
    }

    public func collect() throws {
        try fileStore.createDirectory(at: installedPaths.centralGuestLogsDirectory, withIntermediateDirectories: true)
        try sync(source: installedPaths.bootstrapLog, destination: installedPaths.centralBootstrapLog)
        try sync(source: installedPaths.updateActivationLog, destination: installedPaths.centralUpdateActivationLog)
        try sync(source: installedPaths.updateShutdownLog, destination: installedPaths.centralUpdateShutdownLog)
        try sync(source: installedPaths.datastoreRepairLog, destination: installedPaths.centralDatastoreRepairLog)
        try sync(source: installedPaths.redisBackupLog, destination: installedPaths.centralRedisBackupLog)
        try sync(source: installedPaths.containerLogs, destination: installedPaths.centralContainerLogs)
        try syncRotatedContainerLogs()
    }

    private func syncRotatedContainerLogs() throws {
        guard fileStore.directoryExists(installedPaths.guestRunDirectory) else {
            return
        }
        let entries = try fileStore.contentsOfDirectory(at: installedPaths.guestRunDirectory, skipsHiddenFiles: true)
        for source in entries where source.lastPathComponent.hasPrefix("container-logs.log.") {
            let destination = installedPaths.centralGuestLogsDirectory.appendingPathComponent(source.lastPathComponent)
            try sync(source: source, destination: destination)
        }
    }

    private func sync(source: URL, destination: URL) throws {
        guard fileStore.fileExists(source) else {
            return
        }
        try fileStore.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard fileStore.fileExists(destination) else {
            try fileStore.copyItem(at: source, to: destination)
            return
        }

        let sourceSize = try fileStore.fileSize(source)
        let destinationSize = try fileStore.fileSize(destination)
        guard sourceSize != destinationSize else {
            if try !matchingBytes(source: source, destination: destination, comparedBytes: destinationSize) {
                try replaceDestination(source: source, destination: destination)
            }
            return
        }
        guard sourceSize > destinationSize else {
            try replaceDestination(source: source, destination: destination)
            return
        }
        guard try matchingBytes(source: source, destination: destination, comparedBytes: destinationSize) else {
            try replaceDestination(source: source, destination: destination)
            return
        }
        try appendNewBytes(from: source, to: destination, offset: destinationSize)
    }

    private func replaceDestination(source: URL, destination: URL) throws {
        if fileStore.fileExists(destination) {
            try archive(destination)
        }
        try fileStore.copyItem(at: source, to: destination)
    }

    private func matchingBytes(source: URL, destination: URL, comparedBytes: UInt64) throws -> Bool {
        let length = min(comparedBytes, Self.appendValidationByteLimit)
        if length == 0 {
            return true
        }
        let offset = comparedBytes - length
        guard let sourceData = try readData(source, offset: offset, length: length),
              let destinationData = try readData(destination, offset: offset, length: length) else {
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

    private func archive(_ url: URL) throws {
        let timestamp = archiveTimestampFormatter.string(from: Date())
        let archiveDirectory = installedPaths.logArchiveDirectory
            .appendingPathComponent("guest", isDirectory: true)
        try fileStore.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let destination = uniqueArchiveURL(
            archiveDirectory.appendingPathComponent("\(url.lastPathComponent).\(timestamp)")
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

    private func appendNewBytes(from source: URL, to destination: URL, offset: UInt64) throws {
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer {
            try? sourceHandle.close()
        }
        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer {
            try? destinationHandle.close()
        }
        try sourceHandle.seek(toOffset: offset)
        try destinationHandle.seekToEnd()
        while let data = try sourceHandle.read(upToCount: 256 * 1024), !data.isEmpty {
            try destinationHandle.write(contentsOf: data)
        }
    }
}

private let archiveTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
}()
