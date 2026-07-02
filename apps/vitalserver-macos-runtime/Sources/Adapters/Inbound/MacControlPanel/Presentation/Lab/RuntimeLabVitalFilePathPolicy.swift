import Foundation

struct RuntimeLabVitalFilePathPolicy {
    static let defaultGuestMountPath = "/mnt/tirosh-vital-files"

    func guestPath(
        hostFilePath: String,
        hostRootPath: String,
        guestRootPath: String = RuntimeLabVitalFilePathPolicy.defaultGuestMountPath
    ) -> String? {
        let filePath = normalizedAbsolutePath(hostFilePath)
        let hostRoot = normalizedAbsolutePath(hostRootPath)
        let guestRoot = normalizedAbsolutePath(guestRootPath)
        guard !filePath.isEmpty, !hostRoot.isEmpty, !guestRoot.isEmpty else {
            return nil
        }
        guard filePath == hostRoot || filePath.hasPrefix("\(hostRoot)/") else {
            return nil
        }
        let suffix = String(filePath.dropFirst(hostRoot.count))
        return suffix.isEmpty ? guestRoot : "\(guestRoot)\(suffix)"
    }

    private func normalizedAbsolutePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }
}
