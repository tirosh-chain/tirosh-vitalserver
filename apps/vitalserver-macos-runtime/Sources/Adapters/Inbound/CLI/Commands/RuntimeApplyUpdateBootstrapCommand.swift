import Foundation

public struct RuntimeApplyUpdateBootstrapCommand: Equatable, Sendable {
    public let bundleURL: URL
    public let requestId: String

    public init(bundleURL: URL, requestId: String) {
        self.bundleURL = bundleURL
        self.requestId = requestId
    }
}
