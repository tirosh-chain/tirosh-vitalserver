import CryptoKit
import Contracts
import Domain
import Foundation
import Errors

public struct RuntimeBundleVerificationFileReaderOperations {
    public let readData: (URL) throws -> Data
    public let readUTF8Text: (URL) throws -> String
    public let fileSize: (URL) throws -> UInt64
    public let log: (String) -> Void

    public init(
        readData: @escaping (URL) throws -> Data,
        readUTF8Text: @escaping (URL) throws -> String,
        fileSize: @escaping (URL) throws -> UInt64,
        log: @escaping (String) -> Void
    ) {
        self.readData = readData
        self.readUTF8Text = readUTF8Text
        self.fileSize = fileSize
        self.log = log
    }
}

public struct RuntimeBundleVerificationFileReader {
    private let operations: RuntimeBundleVerificationFileReaderOperations

    public init(operations: RuntimeBundleVerificationFileReaderOperations) {
        self.operations = operations
    }

    public func loadManifest(_ url: URL) throws -> UpdateBundleManifest {
        let data = try operations.readData(url)
        return try JSONDecoder().decode(UpdateBundleManifest.self, from: data)
    }

    public func loadChecksums(_ url: URL) throws -> [String: String] {
        let text = try operations.readUTF8Text(url)
        return UpdateBundleChecksumFileParser.parse(text)
    }

    public func makeVerificationPlan(
        manifest: UpdateBundleManifest,
        expectedProduct: String
    ) throws -> UpdateBundleVerificationPlan {
        do {
            return try UpdateBundleVerifier.makePlan(
                manifest: manifest,
                expectedProduct: expectedProduct
            )
        } catch let error as UpdateBundleVerificationError {
            throw launcherError(error)
        }
    }

    public func verifyDigest(
        url: URL,
        fileVerification: UpdateBundleFileVerification,
        checksumMap: [String: String]
    ) throws {
        do {
            try RuntimeBundleDigestVerifier(
                operations: RuntimeBundleDigestVerificationOperations(
                    sha256: sha256,
                    fileSize: operations.fileSize,
                    log: operations.log
                )
            ).verify(input: RuntimeBundleDigestVerificationInput(
                fileURL: url,
                fileVerification: fileVerification,
                checksumMap: checksumMap
            ))
        } catch let error as UpdateBundleVerificationError {
            throw launcherError(error)
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let data = try operations.readData(url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func launcherError(_ error: UpdateBundleVerificationError) -> LauncherError {
        switch error {
        case .unsupportedSchema(let schemaVersion):
            return .missingArgument("unsupported bundle schema: \(schemaVersion)")
        case .unsupportedProduct(let product):
            return .missingArgument("unsupported bundle product: \(product)")
        case .invalidArtifactName(let name):
            return .missingArgument("invalid artifact name: \(name)")
        case .invalidMigrationName(let name):
            return .missingArgument("invalid migration name: \(name)")
        case .unsupportedArtifactType(let type):
            return .bundleVerificationFailed("unsupported artifact type: \(type)")
        case .manifestChecksumMismatch(let checksumKey):
            return .bundleVerificationFailed("manifest checksum mismatch for \(checksumKey)")
        case .checksumFileMismatch(let checksumKey):
            return .bundleVerificationFailed("checksums.txt mismatch for \(checksumKey)")
        case .sizeMismatch(let checksumKey):
            return .bundleVerificationFailed("size mismatch for \(checksumKey)")
        }
    }
}
