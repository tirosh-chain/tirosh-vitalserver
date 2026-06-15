import Foundation
import Application
import Errors

struct RuntimeLogCollectionPathInspector {
    private let fileStore: RuntimeFileStore

    init(fileStore: RuntimeFileStore) {
        self.fileStore = fileStore
    }

    func expectedLogFileIsPresent(_ url: URL) throws -> Bool {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            return true
        case .missing:
            return false
        case .inspectFailed(let reason):
            throw RuntimeControlLogCollectorError.pathInspectionFailed(path: url.path, reason: reason)
        case .directory, .other, .unknown:
            throw RuntimeControlLogCollectorError.unexpectedPathState(path: url.path, state: state.rawValue)
        }
    }

    func expectedDirectoryIsPresent(_ url: URL) throws -> Bool {
        let state = fileStore.pathState(at: url)
        switch state {
        case .directory:
            return true
        case .missing:
            return false
        case .inspectFailed(let reason):
            throw RuntimeControlLogCollectorError.pathInspectionFailed(path: url.path, reason: reason)
        case .file, .other, .unknown:
            throw RuntimeControlLogCollectorError.unexpectedPathState(path: url.path, state: state.rawValue)
        }
    }

    func pathIsPresent(_ url: URL) throws -> Bool {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file, .directory:
            return true
        case .missing:
            return false
        case .inspectFailed(let reason):
            throw RuntimeControlLogCollectorError.pathInspectionFailed(path: url.path, reason: reason)
        case .other, .unknown:
            throw RuntimeControlLogCollectorError.unexpectedPathState(path: url.path, state: state.rawValue)
        }
    }
}
