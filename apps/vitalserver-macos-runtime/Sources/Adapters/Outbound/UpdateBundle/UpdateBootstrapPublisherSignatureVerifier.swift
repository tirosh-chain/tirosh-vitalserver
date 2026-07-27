import Application
import Contracts
import CryptoKit
import Foundation

public struct UpdateBootstrapPublisherSignatureVerifier {
    private let publicKeysById: [String: Data]

    public init(publicKeysById: [String: Data]) {
        self.publicKeysById = publicKeysById
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
        guard let publicKeyData = publicKeysById[keyId] else {
            return .keyUnavailable(keyId: keyId)
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
