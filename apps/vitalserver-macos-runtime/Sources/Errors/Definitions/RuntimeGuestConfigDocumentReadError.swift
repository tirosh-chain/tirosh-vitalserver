import Foundation

public enum RuntimeGuestConfigDocumentReadError: Error, Equatable {
    case missingFile(String)
}
