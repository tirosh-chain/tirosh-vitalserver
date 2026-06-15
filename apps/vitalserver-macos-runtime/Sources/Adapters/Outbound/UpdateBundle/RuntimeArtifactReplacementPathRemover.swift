import Contracts
import Foundation
import Errors

struct RuntimeArtifactReplacementPathRemover {
    var pathState: (URL) -> RuntimePathState
    var removeItem: (URL) throws -> Void

    func removePathIfPresent(_ url: URL) throws {
        switch pathState(url) {
        case .file, .directory, .other:
            try removeItem(url)
        case .missing:
            return
        case .inspectFailed(let reason):
            throw RuntimeArtifactReplacementError.pathInspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            throw RuntimeArtifactReplacementError.unexpectedPathState(path: url.path, state: value)
        }
    }
}
