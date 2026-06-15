import Foundation

public struct RuntimeMaterializedBundle: Equatable, Sendable {
    public let bundleURL: URL
    public let temporaryRoot: URL?

    public init(bundleURL: URL, temporaryRoot: URL?) {
        self.bundleURL = bundleURL
        self.temporaryRoot = temporaryRoot
    }
}

public struct RuntimeBundleStagingInput: Equatable, Sendable {
    public let sourceURL: URL
    public let bundleURL: URL
    public let manifestVersion: String

    public init(
        sourceURL: URL,
        bundleURL: URL,
        manifestVersion: String
    ) {
        self.sourceURL = sourceURL
        self.bundleURL = bundleURL
        self.manifestVersion = manifestVersion
    }
}
