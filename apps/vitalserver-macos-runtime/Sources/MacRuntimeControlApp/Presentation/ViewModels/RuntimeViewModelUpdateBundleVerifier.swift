import Foundation
import RuntimeControl

struct RuntimeViewModelUpdateBundleVerificationResult: Equatable {
    let isVerified: Bool
    let verification: String
    let message: String
}

@MainActor
struct RuntimeViewModelUpdateBundleVerifier {
    var processMessageFormatter = RuntimeProcessMessageFormatter()

    func verify(
        bundleURL: URL,
        verifyBundle: (URL) async throws -> RuntimeCommandResult
    ) async -> RuntimeViewModelUpdateBundleVerificationResult {
        let result: RuntimeCommandResult
        do {
            result = try await verifyBundle(bundleURL)
        } catch {
            return RuntimeViewModelUpdateBundleVerificationResult(
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
            return RuntimeViewModelUpdateBundleVerificationResult(
                isVerified: true,
                verification: verification,
                message: verification
            )
        }

        let verification = processMessageFormatter.message(
            title: AppConstants.StatusText.updateBundleVerificationFailed,
            result: result
        )
        return RuntimeViewModelUpdateBundleVerificationResult(
            isVerified: false,
            verification: verification,
            message: verification
        )
    }
}
