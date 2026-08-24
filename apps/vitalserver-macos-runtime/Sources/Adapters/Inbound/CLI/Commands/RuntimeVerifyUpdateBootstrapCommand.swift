import Foundation

public struct RuntimeVerifyUpdateBootstrapCommand: Equatable, Sendable {
    public let bundleURL: URL
    public let verificationInvocationId: String?

    public init(bundleURL: URL, verificationInvocationId: String? = nil) {
        self.bundleURL = bundleURL
        self.verificationInvocationId = verificationInvocationId
    }
}
