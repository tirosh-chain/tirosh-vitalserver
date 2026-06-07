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
        try UpdateBundleVerifier.makePlan(
            manifest: manifest,
            expectedProduct: expectedProduct
        )
    }

    public func verifyDigest(
        url: URL,
        fileVerification: UpdateBundleFileVerification,
        checksumMap: [String: String]
    ) throws {
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
    }

    private func sha256(_ url: URL) throws -> String {
        let data = try operations.readData(url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

}
