import Foundation
import Core
import Contracts

public struct RuntimeStorageCapacityValues: Equatable, Sendable {
    public let total: Int?
    public let availableForImportantUsage: Int64?
    public let available: Int?

    public init(
        total: Int?,
        availableForImportantUsage: Int64?,
        available: Int?
    ) {
        self.total = total
        self.availableForImportantUsage = availableForImportantUsage
        self.available = available
    }
}

public struct SystemRuntimeStorageUsageProvider: RuntimeStorageUsageProviding {
    private let fileStore: RuntimeFileStore
    private let loadCapacityValues: (URL) throws -> RuntimeStorageCapacityValues

    public init(
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        loadCapacityValues: @escaping (URL) throws -> RuntimeStorageCapacityValues = { url in
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
                .volumeTotalCapacityKey,
            ])
            return RuntimeStorageCapacityValues(
                total: values.volumeTotalCapacity,
                availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage,
                available: values.volumeAvailableCapacity
            )
        }
    ) {
        self.fileStore = fileStore
        self.loadCapacityValues = loadCapacityValues
    }

    public func storageUsage(for path: String) -> RuntimeStorageUsageResult {
        guard let volumeURL = existingStorageURL(for: path) else {
            return .unavailable
        }
        do {
            let values = try loadCapacityValues(volumeURL)
            guard let total = values.total, total > 0 else {
                return .unavailable
            }

            let available: Int64
            if let importantUsageCapacity = values.availableForImportantUsage {
                available = importantUsageCapacity
            } else if let standardCapacity = values.available {
                available = Int64(standardCapacity)
            } else {
                return .unavailable
            }
            return .loaded(
                ResourceUsage(
                    usedBytes: max(Int64(total) - available, 0),
                    totalBytes: Int64(total)
                )
            )
        } catch {
            return .failed(error.localizedDescription)
        }
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
