import Contracts
import Foundation
import Errors

public struct RuntimeBundleStagingContext: Equatable, Sendable {
    public let bundlesDirectory: URL
    public let updateFreeSpaceMarginBytes: UInt64

    public init(
        bundlesDirectory: URL,
        updateFreeSpaceMarginBytes: UInt64
    ) {
        self.bundlesDirectory = bundlesDirectory
        self.updateFreeSpaceMarginBytes = updateFreeSpaceMarginBytes
    }
}

public struct RuntimeBundleStagingOperations {
    public let directorySize: (URL) throws -> UInt64
    public let compressedSourceSize: (URL) throws -> UInt64
    public let fileExists: (URL) -> Bool
    public let directoryExists: (URL) -> Bool
    public let createDirectory: (URL, Bool) throws -> Void
    public let removeItem: (URL) throws -> Void
    public let copyItem: (URL, URL) throws -> Void
    public let requireFreeSpace: (URL, UInt64, RuntimeOperation) throws -> Void
    public let log: (String) -> Void

    public init(
        directorySize: @escaping (URL) throws -> UInt64,
        compressedSourceSize: @escaping (URL) throws -> UInt64,
        fileExists: @escaping (URL) -> Bool,
        directoryExists: @escaping (URL) -> Bool,
        createDirectory: @escaping (URL, Bool) throws -> Void,
        removeItem: @escaping (URL) throws -> Void,
        copyItem: @escaping (URL, URL) throws -> Void,
        requireFreeSpace: @escaping (URL, UInt64, RuntimeOperation) throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.directorySize = directorySize
        self.compressedSourceSize = compressedSourceSize
        self.fileExists = fileExists
        self.directoryExists = directoryExists
        self.createDirectory = createDirectory
        self.removeItem = removeItem
        self.copyItem = copyItem
        self.requireFreeSpace = requireFreeSpace
        self.log = log
    }
}

public struct RuntimeBundleStager {
    public let context: RuntimeBundleStagingContext
    public let operations: RuntimeBundleStagingOperations

    public init(
        context: RuntimeBundleStagingContext,
        operations: RuntimeBundleStagingOperations
    ) {
        self.context = context
        self.operations = operations
    }

    public func stage(input: RuntimeBundleStagingInput) throws -> URL {
        let destination = context.bundlesDirectory.appendingPathComponent("update-bundle-\(input.manifestVersion)")
        let bundleSize = try operations.directorySize(input.bundleURL)

        try operations.createDirectory(context.bundlesDirectory, true)
        if operations.fileExists(destination) || operations.directoryExists(destination) {
            operations.log("removing existing staged bundle path=\(destination.path)")
            try operations.removeItem(destination)
        }
        try operations.requireFreeSpace(
            context.bundlesDirectory,
            bundleSize + operations.compressedSourceSize(input.sourceURL) + context.updateFreeSpaceMarginBytes,
            .stageBundle
        )
        operations.log(
            "copying bundle to managed storage source=\(input.bundleURL.path) destination=\(destination.path) size=\(formatBytes(bundleSize))"
        )
        try operations.copyItem(input.bundleURL, destination)
        operations.log("bundle stage completed destination=\(destination.path)")
        return destination
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
