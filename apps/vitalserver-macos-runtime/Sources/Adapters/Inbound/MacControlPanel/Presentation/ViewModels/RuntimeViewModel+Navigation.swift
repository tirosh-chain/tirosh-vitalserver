import Foundation
import Contracts
import RuntimeControl
import Errors

@MainActor
public extension RuntimeViewModel {
    func openVitalFilesDirectory() {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        openFolder(runtimeSettings.vitalFilesDirectory)
    }

    func openFolder(_ path: String) {
        if case let .failed(errorMessage) = navigationCoordinator.openFolder(path, nativeShell: nativeShell) {
            message = errorMessage
        }
    }

    func vitalFileFoldersResult() -> Result<[VitalFilesFolder], Error> {
        Result {
            try hostClient.vitalFileFolders(root: runtimeSettings.vitalFilesDirectory)
        }
    }

    func openVitalServer() {
        guard let proxyPort = status.publicProxyPort else {
            message = RuntimeHTTPStatusText.missingProxyPort
            return
        }
        openRuntimeURL(AppConstants.Product.vitalServerURL(proxyPort: proxyPort))
    }

    func openRuntimeControlPWA() {
        openRuntimeURL(AppConstants.Product.runtimeControlPWAURL(port: settings.runtimeControlPort))
    }

    func openExternalURL(_ rawURL: String) {
        openRuntimeURL(rawURL)
    }

    func openRedisUI() {
        guard let proxyPort = status.publicProxyPort else {
            message = RuntimeHTTPStatusText.missingProxyPort
            return
        }
        openRuntimeURL(AppConstants.Product.redisUIURL(proxyPort: proxyPort))
    }

    func openSwagger() {
        guard let proxyPort = status.publicProxyPort else {
            message = RuntimeHTTPStatusText.missingProxyPort
            return
        }
        openRuntimeURL(AppConstants.Product.swaggerURL(proxyPort: proxyPort))
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
        if case let .failed(errorMessage) = navigationCoordinator.openWebURL(rawURL, nativeShell: nativeShell) {
            message = errorMessage
        }
    }
}
