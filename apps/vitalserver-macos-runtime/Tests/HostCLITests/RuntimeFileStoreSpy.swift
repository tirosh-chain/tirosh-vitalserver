import Foundation
import Core
import Contracts

final class RuntimeFileStoreSpy: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    var files: [URL: Data] = [:]
    var modificationDates: [URL: Date] = [:]
    var directories: Set<URL> = []
    var removed: [URL] = []
    var fileSizeErrors: [URL: Error] = [:]
    var modificationDateErrors: [URL: Error] = [:]
    var childDirectoriesError: Error?
    var createDirectoryError: Error?
    var removeItemError: Error?

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        directories.contains(url)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        fileExists(URL(fileURLWithPath: path))
    }

    func readData(_ url: URL) throws -> Data {
        guard let data = files[url] else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return data
    }

    func readUTF8Text(_ url: URL) throws -> String {
        String(decoding: try readData(url), as: UTF8.self)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        if let error = fileSizeErrors[url] {
            throw error
        }
        return UInt64(try readData(url).count)
    }

    func modificationDate(_ url: URL) throws -> Date {
        if let error = modificationDateErrors[url] {
            throw error
        }
        guard let date = modificationDates[url] else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return date
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        files[url] = data
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {
        files[url] = data
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        if let createDirectoryError {
            throw createDirectoryError
        }
        directories.insert(url)
    }

    func removeItem(at url: URL) throws {
        if let removeItemError {
            throw removeItemError
        }
        files.removeValue(forKey: url)
        directories.remove(url)
        removed.append(url)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
        files.removeValue(forKey: source)
    }

    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        files.keys.filter { $0.deletingLastPathComponent() == url }
    }

    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        if let childDirectoriesError {
            throw childDirectoriesError
        }
        return directories.filter {
            $0.deletingLastPathComponent() == url && $0.lastPathComponent.contains(fragment)
        }
    }

    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 {
        files.reduce(UInt64(0)) { total, entry in
            entry.key.path.hasPrefix(url.path) ? total + UInt64(entry.value.count) : total
        }
    }

    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}
