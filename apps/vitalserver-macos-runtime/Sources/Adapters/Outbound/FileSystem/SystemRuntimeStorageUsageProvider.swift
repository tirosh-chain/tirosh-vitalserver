import Foundation
import Application
import Contracts
import Errors

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
        let volumeURLRead = existingStorageURL(for: path)
        guard let volumeURL = volumeURLRead.url else {
            if let failure = volumeURLRead.failure {
                return .failed(failure)
            }
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

    private func existingStorageURL(for path: String) -> RuntimeStorageVolumeURLRead {
        var url = URL(fileURLWithPath: path)
        while true {
            let state = fileStore.pathState(at: url)
            switch state {
            case .file, .directory, .other:
                return .loaded(url)
            case .missing:
                break
            case .inspectFailed(let reason):
                return .failed("storage path inspection failed path=\(url.path) reason=\(reason)")
            case .unknown(let rawValue):
                return .failed("storage path state is unknown path=\(url.path) state=\(rawValue)")
            }
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else {
                return .unavailable
            }
            url = parent
        }
    }
}

private struct RuntimeStorageVolumeURLRead {
    let url: URL?
    let failure: String?

    static func loaded(_ url: URL) -> RuntimeStorageVolumeURLRead {
        RuntimeStorageVolumeURLRead(url: url, failure: nil)
    }

    static var unavailable: RuntimeStorageVolumeURLRead {
        RuntimeStorageVolumeURLRead(url: nil, failure: nil)
    }

    static func failed(_ message: String) -> RuntimeStorageVolumeURLRead {
        RuntimeStorageVolumeURLRead(url: nil, failure: message)
    }
}
