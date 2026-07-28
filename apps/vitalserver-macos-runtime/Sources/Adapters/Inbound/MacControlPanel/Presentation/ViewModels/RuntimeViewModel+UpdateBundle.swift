import Foundation
import RuntimeControl
import Errors

@MainActor
extension RuntimeViewModel {
    func chooseUpdateBundle() async {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        if let url = nativeShell.chooseUpdateBundle(prompt: AppConstants.Actions.chooseBundle) {
            selectedBundleURL = url
            selectedBundleSummary = hostClient.updateBundleSummaryResult(url: url)
                .displayTextForUpdateBundleSummary()
            selectedBundleVerified = false
            selectedBundleVerification = AppConstants.StatusText.updateBundleVerifying
            await verifySelectedBundle()
        }
    }

    func applySelectedBundle() async {
        guard controlClient.capabilities.canApplyBundle else {
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
            action: { try await self.hostClient.applyUpdateBundle(url: bundleURL) }
        ).isSuccess
        if didApply {
            message = AppConstants.StatusText.updateBundleAppliedRelaunching
            relaunchHelper()
            return
        }
        await refreshHealthStatus()
    }

    func verifySelectedBundle() async {
        guard controlClient.capabilities.canOpenLocalFiles else {
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
        operationDetail = AppConstants.StatusText.updateBundleVerifying
        let result = await updateBundleVerifier.verify(
            bundleURL: bundleURL,
            verifyBundle: { try await self.hostClient.verifyUpdateBundle(url: $0) }
        )
        selectedBundleVerified = result.isVerified
        selectedBundleVerification = result.verification
        message = result.message
    }
}

private extension RuntimeHostTextReadResult {
    func displayTextForUpdateBundleSummary() -> String {
        RuntimeHostTextDisplayPolicy(noDataText: AppConstants.StatusText.notReported)
            .displayText(self)
    }
}
