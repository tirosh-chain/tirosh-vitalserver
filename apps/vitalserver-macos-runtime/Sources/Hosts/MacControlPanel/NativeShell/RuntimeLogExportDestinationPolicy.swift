import Foundation
import Contracts
import InboundAdapters
import Errors

protocol RuntimePathPermissionFileManaging {
    func pathState(atPath path: String) -> RuntimePathState
    func isWritableFile(atPath path: String) -> Bool
}

extension FileManager: RuntimePathPermissionFileManaging {
    func pathState(atPath path: String) -> RuntimePathState {
        do {
            let attributes = try attributesOfItem(atPath: path)
            guard let type = attributes[.type] as? FileAttributeType else {
                return .other("missing-file-type")
            }
            switch type {
            case .typeRegular:
                return .file
            case .typeDirectory:
                return .directory
            default:
                return .other(type.rawValue)
            }
        } catch {
            return isNoSuchFile(error) ? .missing : .inspectFailed(error.localizedDescription)
        }
    }

    private func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}

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

    private func existingDirectoryState(_ url: URL) -> RuntimeLogExportPathInspection {
        switch fileManager.pathState(atPath: url.path) {
        case .directory:
            return .directory
        case .file, .other, .unknown, .missing:
            return .notDirectory
        case .inspectFailed(let reason):
            return .failed("destination path inspection failed: \(url.path) reason=\(reason)")
        }
    }

    private func nearestExistingDirectory(from url: URL) -> RuntimeLogExportNearestDirectoryInspection {
        var candidate = url.standardizedFileURL
        while true {
            switch fileManager.pathState(atPath: candidate.path) {
            case .directory:
                return .found(candidate)
            case .file, .other, .unknown:
                return .notDirectory
            case .inspectFailed(let reason):
                return .failed("parent directory path inspection failed: \(candidate.path) reason=\(reason)")
            case .missing:
                break
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return .missing
            }
            candidate = parent
        }
    }

    private func destinationFacts(for url: URL) -> RuntimeLogExportDestinationFacts {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
        let destinationState = existingDirectoryState(standardized)
        let nearestDirectory = nearestExistingDirectoryState(from: parent)
        return RuntimeLogExportDestinationFacts(
            isFileURL: url.isFileURL,
            path: standardized.path,
            pathExtension: standardized.pathExtension,
            isExistingDirectoryDestination: destinationState.isDirectory,
            nearestExistingDirectory: nearestDirectory.directory,
            pathInspectionFailure: destinationState.failureMessage ?? nearestDirectory.failureMessage
        )
    }

    private func nearestExistingDirectoryState(from url: URL) -> RuntimeLogExportNearestDirectoryState {
        switch nearestExistingDirectory(from: url) {
        case .found(let directory):
            return RuntimeLogExportNearestDirectoryState(
                directory: RuntimeLogExportDirectoryState(
                    path: directory.path,
                    isWritable: fileManager.isWritableFile(atPath: directory.path)
                ),
                failureMessage: nil
            )
        case .failed(let message):
            return RuntimeLogExportNearestDirectoryState(directory: nil, failureMessage: message)
        case .missing, .notDirectory:
            return RuntimeLogExportNearestDirectoryState(directory: nil, failureMessage: nil)
        }
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
        case .pathInspectionFailed(let message):
            return AppConstants.StatusText.logExportDestinationInspectionFailed(message)
        }
    }
}

private enum RuntimeLogExportPathInspection {
    case directory
    case notDirectory
    case failed(String)

    var isDirectory: Bool {
        switch self {
        case .directory:
            return true
        case .notDirectory, .failed:
            return false
        }
    }

    var failureMessage: String? {
        guard case .failed(let message) = self else {
            return nil
        }
        return message
    }
}

private enum RuntimeLogExportNearestDirectoryInspection {
    case found(URL)
    case missing
    case notDirectory
    case failed(String)
}

private struct RuntimeLogExportNearestDirectoryState {
    let directory: RuntimeLogExportDirectoryState?
    let failureMessage: String?
}
