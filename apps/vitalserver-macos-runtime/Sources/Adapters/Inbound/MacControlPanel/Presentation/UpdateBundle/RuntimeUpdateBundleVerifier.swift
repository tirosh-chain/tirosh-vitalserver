import Foundation
import RuntimeControl
import Errors

struct RuntimeUpdateBundleVerificationResult: Equatable {
    let isVerified: Bool
    let verification: String
    let message: String
}

@MainActor
struct RuntimeUpdateBundleVerifier {
    var processMessageFormatter = RuntimeProcessMessageFormatter()

    func verify(
        bundleURL: URL,
        verifyBundle: (URL) async throws -> RuntimeCommandResult
    ) async -> RuntimeUpdateBundleVerificationResult {
        let result: RuntimeCommandResult
        do {
            result = try await verifyBundle(bundleURL)
        } catch {
            return RuntimeUpdateBundleVerificationResult(
                isVerified: false,
                verification: error.localizedDescription,
                message: error.localizedDescription
            )
        }

        if result.exitCode == 0 {
            let verification = processMessageFormatter.message(
                title: AppConstants.StatusText.updateBundleVerified,
                result: result
            )
            return RuntimeUpdateBundleVerificationResult(
                isVerified: true,
                verification: verification,
                message: verification
            )
        }

        let verification = processMessageFormatter.message(
            title: AppConstants.StatusText.updateBundleVerificationFailed,
            result: result
        )
        return RuntimeUpdateBundleVerificationResult(
            isVerified: false,
            verification: verification,
            message: verification
        )
    }
}
