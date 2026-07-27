public enum UpdateBootstrapBundleLayout {
    public static let envelopeRelativePath = "bootstrap-envelope.json"
}

public enum UpdateBootstrapBundleEntryKind: Equatable, Sendable {
    case regularFile
    case directory
    case other(String)
}

public struct UpdateBootstrapBundleEntry: Equatable, Sendable {
    public let relativePath: String
    public let kind: UpdateBootstrapBundleEntryKind

    public init(
        relativePath: String,
        kind: UpdateBootstrapBundleEntryKind
    ) {
        self.relativePath = relativePath
        self.kind = kind
    }
}
