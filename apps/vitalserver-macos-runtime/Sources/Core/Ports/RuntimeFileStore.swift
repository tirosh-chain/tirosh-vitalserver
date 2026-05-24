import Contracts
import Foundation

public protocol RuntimeTemporaryDirectoryProviding {
    var temporaryDirectory: URL { get }
}

public protocol RuntimeFileReading {
    func fileExists(_ url: URL) -> Bool
    func directoryExists(_ url: URL) -> Bool
    func isExecutableFile(atPath path: String) -> Bool
    func readData(_ url: URL) throws -> Data
    func readUTF8Text(_ url: URL) throws -> String
    func fileSize(_ url: URL) throws -> UInt64
    func modificationDate(_ url: URL) throws -> Date
}

public protocol RuntimeFileWriting {
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func removeItem(at url: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
}

public protocol RuntimeDirectoryListing {
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL]
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL]
}

public protocol RuntimeDirectoryMeasuring {
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64
}

public protocol RuntimeDiskUsageProviding {
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes
}

public struct RuntimeFileSystemAttributes: Equatable, Sendable {
    public let freeBytes: UInt64

    public init(freeBytes: UInt64) {
        self.freeBytes = freeBytes
    }
}

public protocol RuntimeFileStore:
    RuntimeTemporaryDirectoryProviding,
    RuntimeFileReading,
    RuntimeFileWriting,
    RuntimeDirectoryListing,
    RuntimeDirectoryMeasuring,
    RuntimeDiskUsageProviding
{}
