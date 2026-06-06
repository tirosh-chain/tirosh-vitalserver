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
        }
    }
}
