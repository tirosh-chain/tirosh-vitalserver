import Foundation
import RuntimeControl

@MainActor
extension RuntimeViewModel {
    func openVitalFilesDirectory() {
        guard controlClient.capabilities.canOpenLocalFiles else {
            message = AppConstants.StatusText.actionUnavailable
            return
        }
        openFolder(settings.vitalFilesDirectory)
    }

    func openFolder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard nativeShell.directoryExists(url) else {
            guard nativeShell.confirmCreateDirectory(path: path) else {
                return
            }
            do {
                try nativeShell.createDirectory(url)
            } catch {
                message = AppConstants.StatusText.folderCreateFailed(error.localizedDescription)
                return
            }
            nativeShell.openFileURL(url)
            return
        }
        nativeShell.openFileURL(url)
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
        openRuntimeURL(RuntimeControlLocalAPIConstants.pwaURL(port: settings.runtimeControlPort))
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
        openRuntimeURL(RuntimeControlLocalAPIConstants.devConsoleURL)
    }

    private func openRuntimeURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }
        nativeShell.openWebURL(url)
    }
}
