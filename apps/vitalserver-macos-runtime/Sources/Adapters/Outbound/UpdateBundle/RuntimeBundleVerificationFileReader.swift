import CryptoKit
import Contracts
import Foundation
import Errors

public struct RuntimeBundleVerificationFileReaderOperations {
    public let readData: (URL) throws -> Data
    public let readUTF8Text: (URL) throws -> String
    public let parseChecksums: (String) -> [String: String]

    public init(
        readData: @escaping (URL) throws -> Data,
        readUTF8Text: @escaping (URL) throws -> String,
        parseChecksums: @escaping (String) -> [String: String]
    ) {
        self.readData = readData
        self.readUTF8Text = readUTF8Text
        self.parseChecksums = parseChecksums
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
        return operations.parseChecksums(text)
    }

    public func sha256(_ url: URL) throws -> String {
        let data = try operations.readData(url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

}
