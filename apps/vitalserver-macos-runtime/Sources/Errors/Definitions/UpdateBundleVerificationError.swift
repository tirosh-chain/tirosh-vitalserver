import Foundation

public enum UpdateBundleVerificationError: Error, Equatable {
    case unsupportedSchema(Int)
    case unsupportedProduct(String)
    case invalidArtifactName(String)
    case invalidMigrationName(String)
    case unsupportedArtifactType(String)
    case manifestChecksumMismatch(String)
    case checksumFileMismatch(String)
    case sizeMismatch(String)
}
