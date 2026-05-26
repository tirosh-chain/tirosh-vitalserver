import Foundation

struct RuntimeVitalFilesDirectoryPolicy {
    func validationMessage(for path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/") else {
            return AppConstants.StatusText.vitalFilesDirectoryRequired
        }
        return validationMessage(for: URL(fileURLWithPath: trimmed))
    }

    func validationMessage(for url: URL) -> String? {
        guard isAllowed(url) else {
            return AppConstants.StatusText.vitalFilesDirectoryProtected
        }
        return nil
    }

    func isAllowed(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        return !isProtectedUserDirectory(components)
            && !isICloudDriveDirectory(components)
    }

    private func isProtectedUserDirectory(_ components: [String]) -> Bool {
        guard components.count >= 4,
              components[0] == "/",
              components[1] == "Users" else {
            return false
        }
        return ["Desktop", "Documents", "Downloads"].contains(components[3])
    }

    private func isICloudDriveDirectory(_ components: [String]) -> Bool {
        guard let libraryIndex = components.firstIndex(of: "Library") else {
            return false
        }
        let mobileDocumentsIndex = components.index(after: libraryIndex)
        return components.indices.contains(mobileDocumentsIndex)
            && components[mobileDocumentsIndex] == "Mobile Documents"
    }
}
