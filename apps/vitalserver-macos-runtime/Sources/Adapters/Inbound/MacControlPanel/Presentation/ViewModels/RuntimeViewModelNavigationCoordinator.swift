import Foundation
import Errors

@MainActor
struct RuntimeViewModelNavigationCoordinator {
    func openFolder(_ path: String, nativeShell: any RuntimeNativeShell) -> String? {
        let url = URL(fileURLWithPath: path)
        guard nativeShell.directoryExists(url) else {
            guard nativeShell.confirmCreateDirectory(path: path) else {
                return nil
            }
            do {
                try nativeShell.createDirectory(url)
            } catch {
                return AppConstants.StatusText.folderCreateFailed(error.localizedDescription)
            }
            nativeShell.openFileURL(url)
            return nil
        }
        nativeShell.openFileURL(url)
        return nil
    }

    func openWebURL(_ rawURL: String, nativeShell: any RuntimeNativeShell) {
        guard let url = URL(string: rawURL) else {
            return
        }
        nativeShell.openWebURL(url)
    }
}
