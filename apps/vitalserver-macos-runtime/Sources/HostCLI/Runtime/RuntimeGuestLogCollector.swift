import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeGuestLogCollector {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStore

    func collect() throws {
        try fileStore.createDirectory(at: installedPaths.centralGuestLogsDirectory, withIntermediateDirectories: true)
        try sync(source: installedPaths.bootstrapLog, destination: installedPaths.centralBootstrapLog)
        try sync(source: installedPaths.updateActivationLog, destination: installedPaths.centralUpdateActivationLog)
        try sync(source: installedPaths.datastoreRepairLog, destination: installedPaths.centralDatastoreRepairLog)
        try sync(source: installedPaths.redisBackupLog, destination: installedPaths.centralRedisBackupLog)
        try sync(source: installedPaths.containerLogs, destination: installedPaths.centralContainerLogs)
        try syncRotatedContainerLogs()
    }

    private func syncRotatedContainerLogs() throws {
        guard let entries = try? fileStore.contentsOfDirectory(at: installedPaths.guestRunDirectory, skipsHiddenFiles: true) else {
            return
        }
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
            return
        }
        guard sourceSize > destinationSize else {
            try fileStore.removeItem(at: destination)
            try fileStore.copyItem(at: source, to: destination)
            return
        }
        try appendNewBytes(from: source, to: destination, offset: destinationSize)
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
