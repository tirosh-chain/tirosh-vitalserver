import Foundation
import RuntimeControl

public protocol PlatformAgentUpdateBootstrapVerificationInvoking: Sendable {
    func invoke(
        bundleURL: URL,
        spawn: @escaping @Sendable (String) async -> RuntimeCommandResult
    ) async -> RuntimeCommandResult
}
