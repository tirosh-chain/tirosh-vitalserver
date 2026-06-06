import Application
import Contracts
import Foundation

public enum RuntimeGuestConfigDocumentReadError: Error, Equatable {
    case missingFile(String)
}

public enum RuntimeGuestConfigDocumentReader {
    public static func load(
        from url: URL,
        fileStore: RuntimeFileReading
    ) throws -> GuestRuntimeConfigDocument {
        guard fileStore.fileExists(url) else {
            throw RuntimeGuestConfigDocumentReadError.missingFile(url.path)
        }
        let data = try fileStore.readData(url)
        return try GuestRuntimeConfigDocumentMigration.decodeCurrentOrLegacy(data)
    }
}
