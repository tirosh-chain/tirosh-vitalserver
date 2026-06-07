import Foundation
import Application
import Contracts
import Errors

public struct SystemRuntimeFileStore: RuntimeFileStore, RuntimeFilePartialReading, RuntimeFileMetadataWriting {
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

    public func fileState(atPath path: String) -> RuntimeFileState {
        let state = fileState(at: URL(fileURLWithPath: path))
        guard state == .present else {
            return state
        }
        return FileManager.default.isExecutableFile(atPath: path) ? .executable : .present
    }

    public func fileState(at url: URL) -> RuntimeFileState {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return .present
        } catch {
            return isNoSuchFile(error) ? .missing : .inspectFailed(error.localizedDescription)
        }
    }

    public func pathState(at url: URL) -> RuntimePathState {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                return .other("missing-file-type")
            }
            switch type {
            case .typeRegular:
                return .file
            case .typeDirectory:
                return .directory
            default:
                return .other(type.rawValue)
            }
        } catch {
            return isNoSuchFile(error) ? .missing : .inspectFailed(error.localizedDescription)
        }
    }

    public func readData(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func readData(_ url: URL, offset: UInt64?) throws -> Data {
        guard let offset else {
            return try readData(url)
        }
        let size = try fileSize(url)
        guard offset < size else {
            return Data()
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: offset)
        guard let data = try handle.readToEnd() else {
            throw SystemRuntimeFileStoreError.partialReadReturnedNil(path: url.path, offset: offset)
        }
        return data
    }

    public func readUTF8Text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    public func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
            throw SystemRuntimeFileStoreError.missingFileSize(path: url.path)
        }
        return UInt64(fileSize)
    }

    public func modificationDate(_ url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modificationDate = values.contentModificationDate else {
            throw SystemRuntimeFileStoreError.missingModificationDate(path: url.path)
        }
        return modificationDate
    }

    public func setModificationDate(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
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
        return try contents.filter { item in
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            guard let isDirectory = values.isDirectory else {
                throw SystemRuntimeFileStoreError.missingDirectoryFlag(path: item.path)
            }
            return isDirectory && item.lastPathComponent.contains(fragment)
        }
    }

    public func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
        guard let freeBytes = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else {
            throw SystemRuntimeFileStoreError.missingFileSystemFreeSize(path: path)
        }
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
            guard let isRegularFile = values.isRegularFile else {
                throw SystemRuntimeFileStoreError.missingRegularFileFlag(path: fileURL.path)
            }
            if isRegularFile {
                guard let fileSize = values.fileSize else {
                    throw SystemRuntimeFileStoreError.missingFileSize(path: fileURL.path)
                }
                total += UInt64(fileSize)
            }
        }
        return total
    }

    private func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}
