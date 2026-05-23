import Foundation
import Core
import Contracts

public struct SystemRuntimeFileStore: RuntimeFileStore {
    public init() {}

    public var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory
    }

    public func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    public func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func readData(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func readUTF8Text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    public func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }

    public func writeData(_ data: Data, to url: URL, options: Data.WritingOptions = []) throws {
        try data.write(to: url, options: options)
    }

    public func writeData(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions = [],
        posixPermissions: Int
    ) throws {
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: data,
            attributes: [.posixPermissions: posixPermissions]
        ) else {
            try data.write(to: url, options: options)
            try FileManager.default.setAttributes([.posixPermissions: posixPermissions], ofItemAtPath: url.path)
            return
        }
    }

    public func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool = false) throws -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = skipsHiddenFiles ? [.skipsHiddenFiles] : []
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: options
        )
    }

    public func childDirectories(
        at url: URL,
        nameContains fragment: String,
        skipsHiddenFiles: Bool = true
    ) throws -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = skipsHiddenFiles ? [.skipsHiddenFiles] : []
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        )
        return contents.filter { item in
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true && item.lastPathComponent.contains(fragment)
        }
    }

    public func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
        let freeBytes = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        return RuntimeFileSystemAttributes(freeBytes: freeBytes)
    }

    public func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool = true) throws -> UInt64 {
        let options: FileManager.DirectoryEnumerationOptions = skipsHiddenFiles ? [.skipsHiddenFiles] : []
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: options
        ) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += UInt64(values.fileSize ?? 0)
            }
        }
        return total
    }
}
