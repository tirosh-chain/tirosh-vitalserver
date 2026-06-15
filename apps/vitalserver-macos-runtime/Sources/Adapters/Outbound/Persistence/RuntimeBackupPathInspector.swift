import Contracts
import Foundation
import Errors

struct RuntimeBackupPathInspector {
    var pathState: (URL) -> RuntimePathState

    func pathIsPresent(_ url: URL) throws -> Bool {
        switch pathState(url) {
        case .file, .directory, .other:
            return true
        case .missing:
            return false
        case .inspectFailed(let reason):
            throw RuntimeBackupStoreError.pathInspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            throw RuntimeBackupStoreError.unexpectedPathState(path: url.path, state: value)
        }
    }

    func fileIsPresent(_ url: URL) throws -> Bool {
        let state = pathState(url)
        switch state {
        case .file:
            return true
        case .missing:
            return false
        case .directory, .other:
            throw RuntimeBackupStoreError.unexpectedPathState(path: url.path, state: state.rawValue)
        case .inspectFailed(let reason):
            throw RuntimeBackupStoreError.pathInspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            throw RuntimeBackupStoreError.unexpectedPathState(path: url.path, state: value)
        }
    }

    func directoryIsPresent(_ url: URL) throws -> Bool {
        let state = pathState(url)
        switch state {
        case .directory:
            return true
        case .missing:
            return false
        case .file, .other:
            throw RuntimeBackupStoreError.unexpectedPathState(path: url.path, state: state.rawValue)
        case .inspectFailed(let reason):
            throw RuntimeBackupStoreError.pathInspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            throw RuntimeBackupStoreError.unexpectedPathState(path: url.path, state: value)
        }
    }
}
