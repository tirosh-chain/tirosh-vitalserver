import Foundation
import Management

@MainActor
extension RuntimeController {
    func chooseUpdateBundle() async {
        guard runtimeClient.capabilities.canApplyBundle else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        if let url = nativeShell.chooseUpdateBundle(prompt: AppConstants.Actions.chooseBundle) {
            selectedBundleURL = url
            selectedBundleSummary = runtimeClient.updateBundleSummary(url: url)
            selectedBundleVerified = false
            selectedBundleVerification = AppConstants.StatusText.updateBundleVerifying
            await verifySelectedBundle()
        }
    }

    func applySelectedBundle() async {
        guard runtimeClient.capabilities.canApplyBundle else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let bundleURL = selectedBundleURL else {
            message = AppConstants.StatusText.missingBundle
            return
        }
        guard selectedBundleVerified else {
            message = AppConstants.StatusText.updateBundleNotVerified
            return
        }
        let didApply = await runClientAction(
            preparingMessage: AppConstants.StatusText.updateBundlePreparing,
            waitingMessage: AppConstants.StatusText.uninstallWaitingForPrivilege,
            runningMessage: AppConstants.StatusText.updateBundleApplying,
            successMessage: AppConstants.StatusText.updateBundleApplied,
            action: { try await self.runtimeClient.applyUpdateBundle(url: bundleURL) }
        )
        if didApply {
            message = AppConstants.StatusText.updateBundleAppliedRelaunching
            relaunchHelper()
            return
        }
        await refreshHealthStatus()
    }

    func verifySelectedBundle() async {
        guard runtimeClient.capabilities.canApplyBundle else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        guard let bundleURL = selectedBundleURL else {
            selectedBundleVerification = ""
            selectedBundleVerified = false
            message = AppConstants.StatusText.missingBundle
            return
        }

        isBusy = true
        defer { isBusy = false }

        message = AppConstants.StatusText.updateBundleVerifying
        let result: ProcessResult
        do {
            result = try await runtimeClient.verifyUpdateBundle(url: bundleURL)
        } catch {
            selectedBundleVerification = error.localizedDescription
            selectedBundleVerified = false
            message = error.localizedDescription
            return
        }
        if result.exitCode == 0 {
            selectedBundleVerified = true
            selectedBundleVerification = processMessageFormatter.message(
                title: AppConstants.StatusText.updateBundleVerified,
                result: result
            )
            message = selectedBundleVerification
        } else {
            selectedBundleVerified = false
            selectedBundleVerification = processMessageFormatter.message(
                title: AppConstants.StatusText.updateBundleVerificationFailed,
                result: result
            )
            message = selectedBundleVerification
        }
    }
}
