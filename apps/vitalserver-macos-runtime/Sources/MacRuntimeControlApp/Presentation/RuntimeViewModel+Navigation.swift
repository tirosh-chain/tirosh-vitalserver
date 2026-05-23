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
        nativeShell.openFileURL(URL(fileURLWithPath: path))
    }

    func vitalFileFolders() -> [VitalFilesFolder] {
        hostClient.vitalFileFolders(root: settings.vitalFilesDirectory)
    }

    func openVitalServer() {
        openRuntimeURL(AppConstants.Product.vitalServerURL(proxyPort: status.proxyPort))
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

    private func openRuntimeURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }
        nativeShell.openWebURL(url)
    }
}
