import Foundation

protocol RuntimePathPermissionFileManaging {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func isWritableFile(atPath path: String) -> Bool
}

extension FileManager: RuntimePathPermissionFileManaging {}

struct RuntimeLogExportDestinationPolicy {
    private let fileManager: RuntimePathPermissionFileManaging

    init(fileManager: RuntimePathPermissionFileManaging = FileManager.default) {
        self.fileManager = fileManager
    }

    func validationMessage(for url: URL) -> String? {
        guard url.isFileURL, !url.path.isEmpty else {
            return AppConstants.StatusText.logExportDestinationInvalid
        }

        let standardized = url.standardizedFileURL
        if isExistingDirectory(standardized) {
            return AppConstants.StatusText.logExportDestinationDirectory
        }

        if standardized.pathExtension.lowercased() != "zip" {
            return AppConstants.StatusText.logExportDestinationInvalid
        }

        let parent = standardized.deletingLastPathComponent()
        guard canUseDirectory(parent) else {
            return AppConstants.StatusText.logExportDestinationProtected
        }

        guard let writableDirectory = nearestExistingDirectory(from: parent) else {
            return AppConstants.StatusText.logExportDestinationInvalid
        }

        guard fileManager.isWritableFile(atPath: writableDirectory.path) else {
            return AppConstants.StatusText.logExportDestinationNotWritable
        }

        return nil
    }

    func canNavigateDirectory(_ url: URL) -> Bool {
        canUseDirectory(url.standardizedFileURL)
    }

    private func canUseDirectory(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return !isICloudDrivePath(path)
            && !isProtectedUserPath(path)
            && !isSystemManagedPath(path)
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func nearestExistingDirectory(from url: URL) -> URL? {
        var candidate = url.standardizedFileURL
        while true {
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue ? candidate : nil
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }

    private func isICloudDrivePath(_ path: String) -> Bool {
        path.contains("/Library/Mobile Documents/")
            || path.hasSuffix("/Library/Mobile Documents")
    }

    private func isProtectedUserPath(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count >= 4,
              components[0] == "/",
              components[1] == "Users" else {
            return false
        }
        return ["Desktop", "Documents"].contains(components[3])
    }

    private func isSystemManagedPath(_ path: String) -> Bool {
        path == "/"
            || path == "/Applications"
            || path.hasPrefix("/Applications/")
            || path == "/Library"
            || path.hasPrefix("/Library/")
            || path == "/System"
            || path.hasPrefix("/System/")
            || path == "/bin"
            || path.hasPrefix("/bin/")
            || path == "/sbin"
            || path.hasPrefix("/sbin/")
            || path == "/usr"
            || (path.hasPrefix("/usr/") && !path.hasPrefix("/usr/local/"))
    }
}
