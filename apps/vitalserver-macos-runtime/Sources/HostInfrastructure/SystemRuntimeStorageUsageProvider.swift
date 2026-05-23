import Foundation
import Core
import Contracts

public struct SystemRuntimeStorageUsageProvider: RuntimeStorageUsageProviding {
    private let fileStore: RuntimeFileStore

    public init(fileStore: RuntimeFileStore = SystemRuntimeFileStore()) {
        self.fileStore = fileStore
    }

    public func storageUsage(for path: String) -> ResourceUsage? {
        guard let volumeURL = existingStorageURL(for: path),
              let values = try? volumeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
                .volumeTotalCapacityKey,
              ]),
              let total = values.volumeTotalCapacity,
              total > 0 else {
            return nil
        }

        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
            ?? 0
        return ResourceUsage(
            usedBytes: max(Int64(total) - available, 0),
            totalBytes: Int64(total)
        )
    }

    private func existingStorageURL(for path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        while !pathExists(url) {
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else {
                return nil
            }
            url = parent
        }
        return url
    }

    private func pathExists(_ url: URL) -> Bool {
        fileStore.fileExists(url) || fileStore.directoryExists(url)
    }
}
