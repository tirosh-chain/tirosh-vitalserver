import Foundation
import Application
import Contracts
import Domain

final class RuntimeFileStoreSpy: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    var files: [URL: Data] = [:]
    var fileStates: [String: RuntimeFileState] = [:]
    var pathStates: [String: RuntimePathState] = [:]
    var modificationDates: [URL: Date] = [:]
    var directories: Set<URL> = []
    var removed: [URL] = []
    var readDataErrors: [URL: Error] = [:]
    var fileSizeErrors: [URL: Error] = [:]
    var modificationDateErrors: [URL: Error] = [:]
    var childDirectoriesError: Error?
    var createDirectoryError: Error?
    var removeItemError: Error?
    var copyItemError: Error?

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        directories.contains { $0.path == url.path }
    }

    func isExecutableFile(atPath path: String) -> Bool {
        fileExists(URL(fileURLWithPath: path))
    }

    func fileState(atPath path: String) -> RuntimeFileState {
        if let state = fileStates[path] {
            return state
        }
        if isExecutableFile(atPath: path) {
            return .executable
        }
        if fileExists(URL(fileURLWithPath: path)) {
            return .present
        }
        return .missing
    }

    func fileState(at url: URL) -> RuntimeFileState {
        if let state = fileStates[url.path] {
            return state
        }
        return fileExists(url) ? .present : .missing
    }

    func pathState(at url: URL) -> RuntimePathState {
        if let state = pathStates[url.path] {
            return state
        }
        if fileExists(url) {
            return .file
        }
        if directoryExists(url) {
            return .directory
        }
        return .missing
    }

    func readData(_ url: URL) throws -> Data {
        if let error = readDataErrors[url] {
            throw error
        }
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
        if withIntermediateDirectories {
            var current = url
            while current.path != "/" {
                directories.insert(current)
                current = current.deletingLastPathComponent()
            }
            return
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
        if let copyItemError {
            throw copyItemError
        }
        if let data = files[source] {
            files[destination] = data
            return
        }
        if directories.contains(source) {
            directories.insert(destination)
            for directory in Array(directories) where directory.path.hasPrefix(source.path + "/") {
                let suffix = String(directory.path.dropFirst(source.path.count))
                directories.insert(URL(fileURLWithPath: destination.path + suffix))
            }
            for (url, data) in Array(files) where url.path.hasPrefix(source.path + "/") {
                let suffix = String(url.path.dropFirst(source.path.count))
                files[URL(fileURLWithPath: destination.path + suffix)] = data
            }
            return
        }
        _ = try readData(source)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        if let data = files[source] {
            files[destination] = data
            files.removeValue(forKey: source)
            return
        }
        if directories.contains(where: { $0.path == source.path }) {
            directories = Set(directories.filter { $0.path != source.path })
            directories.insert(destination)
            for directory in Array(directories) where directory.path.hasPrefix(source.path + "/") {
                let suffix = String(directory.path.dropFirst(source.path.count))
                directories.remove(directory)
                directories.insert(URL(fileURLWithPath: destination.path + suffix))
            }
            for (url, data) in Array(files) where url.path.hasPrefix(source.path + "/") {
                let suffix = String(url.path.dropFirst(source.path.count))
                files.removeValue(forKey: url)
                files[URL(fileURLWithPath: destination.path + suffix)] = data
            }
            return
        }
        _ = try readData(source)
    }

    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] {
        let childFiles = files.keys.filter { $0.deletingLastPathComponent().path == url.path }
        let childDirectories = directories.filter { $0.deletingLastPathComponent().path == url.path }
        return Array(childFiles) + Array(childDirectories)
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
