import Foundation
import Contracts
import Errors

struct RuntimeLogExportPathInspector {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func pathState(at url: URL) -> RuntimePathState {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
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

    func copyLogDirectory(from source: URL, to destination: URL) throws {
        let sourceState = pathState(at: source)
        switch sourceState {
        case .directory:
            break
        case .missing:
            return
        case .inspectFailed(let reason):
            throw RuntimeLogExporterError.pathInspectionFailed(path: source.path, reason: reason)
        case .file, .other, .unknown:
            throw RuntimeLogExporterError.unexpectedPathState(path: source.path, state: sourceState.rawValue)
        }

        switch pathState(at: destination) {
        case .file, .directory, .other:
            try fileManager.removeItem(at: destination)
        case .missing:
            break
        case .inspectFailed(let reason):
            throw RuntimeLogExporterError.pathInspectionFailed(path: destination.path, reason: reason)
        case .unknown(let state):
            throw RuntimeLogExporterError.unexpectedPathState(path: destination.path, state: state)
        }

        try fileManager.copyItem(at: source, to: destination)
    }

    func ensureBundleRootDirectory(_ bundleRoot: URL) throws {
        let state = pathState(at: bundleRoot)
        switch state {
        case .directory:
            return
        case .missing:
            try fileManager.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        case .inspectFailed(let reason):
            throw RuntimeLogExporterError.pathInspectionFailed(path: bundleRoot.path, reason: reason)
        case .file, .other, .unknown:
            throw RuntimeLogExporterError.unexpectedPathState(path: bundleRoot.path, state: state.rawValue)
        }
    }

    func moveArchiveReplacingFile(from temporaryArchive: URL, to destination: URL) throws {
        let destinationState = pathState(at: destination)
        switch destinationState {
        case .file:
            try fileManager.removeItem(at: destination)
        case .missing:
            break
        case .inspectFailed(let reason):
            throw RuntimeLogExporterError.pathInspectionFailed(path: destination.path, reason: reason)
        case .directory, .other, .unknown:
            throw RuntimeLogExporterError.unexpectedPathState(path: destination.path, state: destinationState.rawValue)
        }
        try fileManager.moveItem(at: temporaryArchive, to: destination)
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
