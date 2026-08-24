import Foundation

public struct RuntimeApplyUpdateBootstrapCommand: Equatable, Sendable {
    public let bundleURL: URL
    public let requestId: String
    public let requirePlatformAgentSelection: Bool

    public init(
        bundleURL: URL,
        requestId: String,
        requirePlatformAgentSelection: Bool = false
    ) {
        self.bundleURL = bundleURL
        self.requestId = requestId
        self.requirePlatformAgentSelection = requirePlatformAgentSelection
    }
}
