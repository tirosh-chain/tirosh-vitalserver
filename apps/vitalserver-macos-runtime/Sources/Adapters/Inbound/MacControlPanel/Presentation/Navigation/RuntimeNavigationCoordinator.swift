import Foundation
import Contracts
import Errors

@MainActor
enum RuntimeNavigationActionResult: Equatable {
    case completed
    case cancelled
    case failed(String)
}

@MainActor
struct RuntimeNavigationCoordinator {
    func openFolder(_ path: String, nativeShell: any RuntimeNativeShell) -> RuntimeNavigationActionResult {
        let url = URL(fileURLWithPath: path)
        let pathState = nativeShell.pathState(url)
        switch pathState {
        case .directory:
            nativeShell.openFileURL(url)
            return .completed
        case .missing:
            guard nativeShell.confirmCreateDirectory(path: path) else {
                return .cancelled
            }
            do {
                try nativeShell.createDirectory(url)
            } catch {
                return .failed(AppConstants.StatusText.folderCreateFailed(error.localizedDescription))
            }
            nativeShell.openFileURL(url)
            return .completed
        case .inspectFailed(let reason):
            return .failed(AppConstants.StatusText.folderReadFailed(reason))
        case .file, .other, .unknown:
            return .failed(AppConstants.StatusText.folderReadFailed(
                "folder path state is unexpected: \(url.path) state=\(pathState.rawValue)"
            ))
        }
    }

    func openWebURL(_ rawURL: String, nativeShell: any RuntimeNativeShell) -> RuntimeNavigationActionResult {
        guard let url = URL(string: rawURL), isWebURL(url) else {
            return .failed(AppConstants.StatusText.invalidRuntimeURL)
        }
        nativeShell.openWebURL(url)
        return .completed
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }
        return url.host?.isEmpty == false
    }
}
