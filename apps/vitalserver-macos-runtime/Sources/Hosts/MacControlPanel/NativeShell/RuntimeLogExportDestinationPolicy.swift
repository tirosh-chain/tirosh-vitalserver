import Foundation
import InboundAdapters
import Errors

protocol RuntimePathPermissionFileManaging {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func isWritableFile(atPath path: String) -> Bool
}

extension FileManager: RuntimePathPermissionFileManaging {}

struct RuntimeLogExportDestinationPolicy {
    private let fileManager: RuntimePathPermissionFileManaging
    private let destinationRule = RuntimeLogExportDestinationRule()

    init(fileManager: RuntimePathPermissionFileManaging = FileManager.default) {
        self.fileManager = fileManager
    }

    func validationMessage(for url: URL) -> String? {
        validationMessage(for: destinationRule.validationResult(for: destinationFacts(for: url)))
    }

    func canNavigateDirectory(_ url: URL) -> Bool {
        destinationRule.canNavigateDirectoryPath(url.standardizedFileURL.path)
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

    private func destinationFacts(for url: URL) -> RuntimeLogExportDestinationFacts {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
        return RuntimeLogExportDestinationFacts(
            isFileURL: url.isFileURL,
            path: standardized.path,
            pathExtension: standardized.pathExtension,
            isExistingDirectoryDestination: isExistingDirectory(standardized),
            nearestExistingDirectory: nearestExistingDirectoryState(from: parent)
        )
    }

    private func nearestExistingDirectoryState(from url: URL) -> RuntimeLogExportDirectoryState? {
        guard let directory = nearestExistingDirectory(from: url) else {
            return nil
        }
        return RuntimeLogExportDirectoryState(
            path: directory.path,
            isWritable: fileManager.isWritableFile(atPath: directory.path)
        )
    }

    private func validationMessage(for result: RuntimeLogExportDestinationValidationResult) -> String? {
        switch result {
        case .valid:
            return nil
        case .invalidDestination:
            return AppConstants.StatusText.logExportDestinationInvalid
        case .existingDirectoryDestination:
            return AppConstants.StatusText.logExportDestinationDirectory
        case .protectedDirectory:
            return AppConstants.StatusText.logExportDestinationProtected
        case .parentDirectoryNotWritable:
            return AppConstants.StatusText.logExportDestinationNotWritable
        }
    }
}
