import Application
import Contracts
import CryptoKit
import Foundation

public struct UpdateBootstrapPublisherSignatureVerifier {
    private let publisherKeysById: [String: TrustedUpdatePublisherKey]

    public init(publisherKeysById: [String: TrustedUpdatePublisherKey]) {
        self.publisherKeysById = publisherKeysById
    }

    public func verify(
        keyId: String,
        algorithm: UpdateBootstrapSignatureAlgorithm,
        payload: Data,
        signature: String
    ) -> UpdateBootstrapPublisherVerificationResult {
        guard algorithm == .ed25519 else {
            return .failed(reason: "unsupported publisher signature algorithm")
        }
        guard let publisherKey = publisherKeysById[keyId] else {
            return .keyUnavailable(keyId: keyId)
        }
        guard publisherKey.state == .active else {
            return .keyRevoked(keyId: keyId)
        }
        guard let publicKeyData = Data(base64Encoded: publisherKey.publicKey) else {
            return .failed(reason: "trusted publisher public key is not valid base64")
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyData
            )
        } catch {
            return .failed(
                reason: "trusted publisher key is invalid: \(error)"
            )
        }

        guard let signatureData = Data(base64Encoded: signature) else {
            return .invalidSignature
        }
        return publicKey.isValidSignature(signatureData, for: payload)
            ? .verified
            : .invalidSignature
    }
}
