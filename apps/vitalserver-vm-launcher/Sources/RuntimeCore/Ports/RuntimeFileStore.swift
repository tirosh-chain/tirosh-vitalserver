import Foundation

public protocol RuntimeFileStore {
    var temporaryDirectory: URL { get }

    func fileExists(_ url: URL) -> Bool
    func directoryExists(_ url: URL) -> Bool
    func isExecutableFile(atPath path: String) -> Bool
    func readData(_ url: URL) throws -> Data
    func readUTF8Text(_ url: URL) throws -> String
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func removeItem(at url: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL]
    func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any]
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator?
}

public struct LocalRuntimeFileStore: RuntimeFileStore {
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

    public func writeData(_ data: Data, to url: URL, options: Data.WritingOptions = []) throws {
        try data.write(to: url, options: options)
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

    public func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }

    public func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfFileSystem(forPath: path)
    }

    public func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}
