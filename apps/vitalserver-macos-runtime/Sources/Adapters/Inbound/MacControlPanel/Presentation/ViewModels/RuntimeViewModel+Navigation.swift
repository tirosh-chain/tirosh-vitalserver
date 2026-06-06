import Foundation
import RuntimeControl
import Errors

@MainActor
public extension RuntimeViewModel {
    func openVitalFilesDirectory() {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        openFolder(settings.vitalFilesDirectory)
    }

    func openFolder(_ path: String) {
        if let errorMessage = navigationCoordinator.openFolder(path, nativeShell: nativeShell) {
            message = errorMessage
        }
    }

    func vitalFileFoldersResult() -> Result<[VitalFilesFolder], Error> {
        Result {
            try hostClient.vitalFileFolders(root: settings.vitalFilesDirectory)
        }
    }

    func openVitalServer() {
        openRuntimeURL(AppConstants.Product.vitalServerURL(proxyPort: status.proxyPort))
    }

    func openRuntimeControlPWA() {
        openRuntimeURL(AppConstants.Product.runtimeControlPWAURL(port: settings.runtimeControlPort))
    }

    func openExternalURL(_ rawURL: String) {
        openRuntimeURL(rawURL)
    }

    func openRedisUI() {
        openRuntimeURL(AppConstants.Product.redisUIURL(proxyPort: status.proxyPort))
    }

    func openSwagger() {
        openRuntimeURL(AppConstants.Product.swaggerURL(proxyPort: status.proxyPort))
    }

    func openTiroshWebsite() {
        openRuntimeURL(AppConstants.Product.tiroshURL)
    }

    func openVitalDBWebsite() {
        openRuntimeURL(AppConstants.Product.vitalDBURL)
    }

    func openRuntimeControlDevConsole() {
        openRuntimeURL(AppConstants.Product.runtimeControlDevConsoleURL(port: settings.runtimeControlPort))
    }

    private func openRuntimeURL(_ rawURL: String) {
        navigationCoordinator.openWebURL(rawURL, nativeShell: nativeShell)
    }
}
