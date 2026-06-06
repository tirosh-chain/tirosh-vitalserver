import Foundation

public enum RuntimeStatusReporterError: Error, Equatable {
    case missingStatusDocumentForProgress
    case statusDocumentReadFailed(String)
}
