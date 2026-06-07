import Application
import Contracts
import Foundation
import OutboundAdapters
import InboundAdapters
import Errors

extension GuestRuntimeConfigDocument {
    static func load(from url: URL, fileStore: RuntimeFileReading) throws -> GuestRuntimeConfigDocument {
        do {
            return try RuntimeGuestConfigDocumentReader.load(from: url, fileStore: fileStore)
        } catch RuntimeGuestConfigDocumentReadError.missingFile(let path) {
            throw LauncherError.missingFile(path)
        } catch RuntimeGuestConfigDocumentReadError.pathInspectionFailed(let path, let reason) {
            throw LauncherError.runtimeOperationFailed(
                "guest runtime config path inspection failed path=\(path) reason=\(reason)"
            )
        } catch RuntimeGuestConfigDocumentReadError.unexpectedPathState(let path, let state) {
            throw LauncherError.runtimeOperationFailed(
                "guest runtime config path state is unexpected path=\(path) state=\(state)"
            )
        }
    }
}
