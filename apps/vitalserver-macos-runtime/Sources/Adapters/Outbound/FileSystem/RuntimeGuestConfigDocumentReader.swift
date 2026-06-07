import Application
import Contracts
import Foundation
import Errors

public enum RuntimeGuestConfigDocumentReader {
    public static func load(
        from url: URL,
        fileStore: RuntimeFileReading
    ) throws -> GuestRuntimeConfigDocument {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            throw RuntimeGuestConfigDocumentReadError.missingFile(url.path)
        case .inspectFailed(let reason):
            throw RuntimeGuestConfigDocumentReadError.pathInspectionFailed(path: url.path, reason: reason)
        case .directory, .other, .unknown:
            throw RuntimeGuestConfigDocumentReadError.unexpectedPathState(path: url.path, state: state.rawValue)
        }
        let data = try fileStore.readData(url)
        return try GuestRuntimeConfigDocumentMigration.decodeCurrentOrLegacy(data)
    }
}
