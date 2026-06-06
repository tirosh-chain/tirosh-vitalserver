import Domain
import Foundation

public struct RuntimeBundleDigestVerificationInput: Equatable, Sendable {
    public let fileURL: URL
    public let fileVerification: UpdateBundleFileVerification
    public let checksumMap: [String: String]

    public init(
        fileURL: URL,
        fileVerification: UpdateBundleFileVerification,
        checksumMap: [String: String]
    ) {
        self.fileURL = fileURL
        self.fileVerification = fileVerification
        self.checksumMap = checksumMap
    }
}

public struct RuntimeBundleDigestVerificationOperations {
    public let sha256: (URL) throws -> String
    public let fileSize: (URL) throws -> UInt64
    public let log: (String) -> Void

    public init(
        sha256: @escaping (URL) throws -> String,
        fileSize: @escaping (URL) throws -> UInt64,
        log: @escaping (String) -> Void
    ) {
        self.sha256 = sha256
        self.fileSize = fileSize
        self.log = log
    }
}

public struct RuntimeBundleDigestVerifier {
    public let operations: RuntimeBundleDigestVerificationOperations

    public init(operations: RuntimeBundleDigestVerificationOperations) {
        self.operations = operations
    }

    public func verify(input: RuntimeBundleDigestVerificationInput) throws {
        operations.log(
            "checksum started key=\(input.fileVerification.checksumKey) path=\(input.fileURL.path) expectedSize=\(formatBytes(bundleItemSize(input.fileVerification.expectedSize)))"
        )
        let actualDigest = try operations.sha256(input.fileURL)
        let size = Int(try operations.fileSize(input.fileURL))
        try UpdateBundleVerifier.verifyDigest(
            checksumKey: input.fileVerification.checksumKey,
            expectedSHA256: input.fileVerification.expectedSHA256,
            expectedSize: input.fileVerification.expectedSize,
            checksumMap: input.checksumMap,
            actualSHA256: actualDigest,
            actualSize: size
        )
        operations.log(
            "checksum completed key=\(input.fileVerification.checksumKey) actualSize=\(formatBytes(bundleItemSize(size)))"
        )
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }

    private func bundleItemSize(_ size: Int) -> UInt64 {
        UInt64(max(size, 0))
    }
}
