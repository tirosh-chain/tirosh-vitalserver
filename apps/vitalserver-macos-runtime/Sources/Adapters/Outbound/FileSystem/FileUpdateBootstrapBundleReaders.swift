import Application
import Contracts
import Foundation

public struct FileUpdateBootstrapEnvelopeReader:
    UpdateBootstrapEnvelopeReading,
    @unchecked Sendable
{
    public let bundleRoot: URL
    public let fileStore: any RuntimeFileReading
    public let decoder: JSONDecoder

    public init(
        bundleRoot: URL,
        fileStore: any RuntimeFileReading,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.bundleRoot = bundleRoot
        self.fileStore = fileStore
        self.decoder = decoder
    }

    public func readEnvelope() -> UpdateBootstrapEnvelopeReadResult {
        let url = bundleRoot.appendingPathComponent(
            UpdateBootstrapBundleLayout.envelopeRelativePath
        )
        let pathState = fileStore.pathState(at: url)
        switch pathState {
        case .file:
            break
        case .missing:
            return .missing(path: url.path)
        case .inspectFailed(let reason):
            return .inspectionFailed(path: url.path, reason: reason)
        case .directory, .other, .unknown:
            return .unexpectedPathState(
                path: url.path,
                state: pathState.rawValue
            )
        }
        let data: Data
        do {
            data = try fileStore.readData(url)
        } catch {
            return .readFailed(path: url.path, reason: error.localizedDescription)
        }
        do {
            return .loaded(
                try decoder.decode(UpdateBootstrapEnvelope.self, from: data)
            )
        } catch {
            return .decodeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }
}

public struct FileUpdateBootstrapBundleEntriesReader:
    UpdateBootstrapBundleEntriesReading,
    @unchecked Sendable
{
    public let bundleRoot: URL
    public let fileStore: any RuntimeFileReading
    public let entryEnumerator: any UpdateBootstrapBundleEntryEnumerating

    public init(
        bundleRoot: URL,
        fileStore: any RuntimeFileReading,
        entryEnumerator: any UpdateBootstrapBundleEntryEnumerating =
            SystemUpdateBootstrapBundleEntryEnumerator()
    ) {
        self.bundleRoot = bundleRoot
        self.fileStore = fileStore
        self.entryEnumerator = entryEnumerator
    }

    public func readEntries() -> UpdateBootstrapBundleEntriesReadResult {
        let rootState = fileStore.pathState(at: bundleRoot)
        switch rootState {
        case .directory:
            break
        case .missing:
            return .rootMissing(path: bundleRoot.path)
        case .inspectFailed(let reason):
            return .rootInspectionFailed(
                path: bundleRoot.path,
                reason: reason
            )
        case .file, .other, .unknown:
            return .unexpectedRootPathState(
                path: bundleRoot.path,
                state: rootState.rawValue
            )
        }
        do {
            return .loaded(try entryEnumerator.entries(beneath: bundleRoot))
        } catch {
            return .listingFailed(
                path: bundleRoot.path,
                reason: error.localizedDescription
            )
        }
    }
}

public protocol UpdateBootstrapBundleEntryEnumerating: Sendable {
    func entries(beneath root: URL) throws -> [UpdateBootstrapBundleEntry]
}

public struct SystemUpdateBootstrapBundleEntryEnumerator:
    UpdateBootstrapBundleEntryEnumerating
{
    public init() {}

    public func entries(
        beneath root: URL
    ) throws -> [UpdateBootstrapBundleEntry] {
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw UpdateBootstrapBundleEnumerationError.unavailable(
                path: root.path
            )
        }

        var entries: [UpdateBootstrapBundleEntry] = []
        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: Set(resourceKeys))
            let kind: UpdateBootstrapBundleEntryKind
            if values.isSymbolicLink == true {
                kind = .other("symbolic-link")
            } else if values.isRegularFile == true {
                kind = .regularFile
            } else if values.isDirectory == true {
                kind = .directory
            } else {
                kind = .other("unsupported")
            }
            entries.append(
                UpdateBootstrapBundleEntry(
                    relativePath: try relativePath(of: item, beneath: root),
                    kind: kind
                )
            )
        }
        if let enumerationError {
            throw enumerationError
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private func relativePath(of item: URL, beneath root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let itemPath = item.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard itemPath.hasPrefix(prefix) else {
            throw UpdateBootstrapBundleEnumerationError.outsideRoot(
                root: rootPath,
                entry: itemPath
            )
        }
        return String(itemPath.dropFirst(prefix.count))
    }
}

public enum UpdateBootstrapBundleEnumerationError:
    Error,
    Equatable,
    LocalizedError
{
    case unavailable(path: String)
    case outsideRoot(root: String, entry: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let path):
            return "bootstrap bundle enumeration unavailable path=\(path)"
        case .outsideRoot(let root, let entry):
            return "bootstrap bundle entry escaped root root=\(root) entry=\(entry)"
        }
    }
}
