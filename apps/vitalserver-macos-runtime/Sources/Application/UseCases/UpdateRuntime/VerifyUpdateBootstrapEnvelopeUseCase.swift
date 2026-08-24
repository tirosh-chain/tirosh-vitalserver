import Contracts
import Domain
import Foundation

public struct VerifyUpdateBootstrapEnvelopeInput: Equatable, Sendable {
    public let envelope: UpdateBootstrapEnvelope
    public let expectedProductId: String
    public let expectedTarget: UpdateBootstrapTarget

    public init(
        envelope: UpdateBootstrapEnvelope,
        expectedProductId: String,
        expectedTarget: UpdateBootstrapTarget
    ) {
        self.envelope = envelope
        self.expectedProductId = expectedProductId
        self.expectedTarget = expectedTarget
    }
}

public enum UpdateBootstrapPublisherVerificationResult: Equatable, Sendable {
    case verified
    case keyUnavailable(keyId: String)
    case keyRevoked(keyId: String)
    case invalidSignature
    case failed(reason: String)
}

public enum UpdateBootstrapArtifactObservation: Equatable, Sendable {
    case available(sha256: String, sizeBytes: Int)
    case unavailable(reason: String)
    case failed(reason: String)
}

public struct VerifyUpdateBootstrapEnvelopeOperations {
    public let canonicalSignedPayload: (UpdateBootstrapEnvelope) throws -> Data
    public let sha256: (Data) -> String
    public let verifyPublisherSignature: (
        _ keyId: String,
        _ algorithm: UpdateBootstrapSignatureAlgorithm,
        _ payload: Data,
        _ signature: String
    ) -> UpdateBootstrapPublisherVerificationResult
    public let observeArtifact: (
        UpdateBootstrapArtifact
    ) -> UpdateBootstrapArtifactObservation

    public init(
        canonicalSignedPayload: @escaping (UpdateBootstrapEnvelope) throws -> Data,
        sha256: @escaping (Data) -> String,
        verifyPublisherSignature: @escaping (
            _ keyId: String,
            _ algorithm: UpdateBootstrapSignatureAlgorithm,
            _ payload: Data,
            _ signature: String
        ) -> UpdateBootstrapPublisherVerificationResult,
        observeArtifact: @escaping (
            UpdateBootstrapArtifact
        ) -> UpdateBootstrapArtifactObservation
    ) {
        self.canonicalSignedPayload = canonicalSignedPayload
        self.sha256 = sha256
        self.verifyPublisherSignature = verifyPublisherSignature
        self.observeArtifact = observeArtifact
    }
}

public enum VerifyUpdateBootstrapEnvelopeError: Error, Equatable, Sendable {
    case envelopeInvalid(UpdateBootstrapEnvelopeValidationError)
    case canonicalPayloadFailed(reason: String)
    case canonicalPayloadDigestMismatch(expected: String, actual: String)
    case publisherKeyUnavailable(keyId: String)
    case publisherKeyRevoked(keyId: String)
    case publisherSignatureInvalid(keyId: String)
    case publisherVerificationFailed(keyId: String, reason: String)
    case artifactUnavailable(artifactId: String, reason: String)
    case artifactInspectionFailed(artifactId: String, reason: String)
    case artifactDigestMismatch(artifactId: String, expected: String, actual: String)
    case artifactSizeMismatch(artifactId: String, expected: Int, actual: Int)
}

public struct VerifyUpdateBootstrapEnvelopeUseCase {
    public init() {}

    public func verify(
        input: VerifyUpdateBootstrapEnvelopeInput,
        operations: VerifyUpdateBootstrapEnvelopeOperations
    ) throws -> VerifiedUpdateBootstrapClosure {
        do {
            try UpdateBootstrapEnvelopePolicy.validate(
                input.envelope,
                expectedProductId: input.expectedProductId,
                expectedTarget: input.expectedTarget
            )
        } catch let error as UpdateBootstrapEnvelopeValidationError {
            throw VerifyUpdateBootstrapEnvelopeError.envelopeInvalid(error)
        }

        let canonicalPayload: Data
        do {
            canonicalPayload = try operations.canonicalSignedPayload(input.envelope)
        } catch {
            throw VerifyUpdateBootstrapEnvelopeError.canonicalPayloadFailed(
                reason: String(describing: error)
            )
        }

        let canonicalPayloadSHA256 = operations.sha256(canonicalPayload)
        guard canonicalPayloadSHA256 == input.envelope.signature.signedSha256 else {
            throw VerifyUpdateBootstrapEnvelopeError.canonicalPayloadDigestMismatch(
                expected: input.envelope.signature.signedSha256,
                actual: canonicalPayloadSHA256
            )
        }

        switch operations.verifyPublisherSignature(
            input.envelope.signature.keyId,
            input.envelope.signature.algorithm,
            canonicalPayload,
            input.envelope.signature.value
        ) {
        case .verified:
            break
        case .keyUnavailable(let keyId):
            throw VerifyUpdateBootstrapEnvelopeError.publisherKeyUnavailable(
                keyId: keyId
            )
        case .keyRevoked(let keyId):
            throw VerifyUpdateBootstrapEnvelopeError.publisherKeyRevoked(
                keyId: keyId
            )
        case .invalidSignature:
            throw VerifyUpdateBootstrapEnvelopeError.publisherSignatureInvalid(
                keyId: input.envelope.signature.keyId
            )
        case .failed(let reason):
            throw VerifyUpdateBootstrapEnvelopeError.publisherVerificationFailed(
                keyId: input.envelope.signature.keyId,
                reason: reason
            )
        }

        let artifacts = [
            input.envelope.nextUpdaterArtifact,
            input.envelope.specification,
        ]
        var verifiedArtifactIds: [String] = []
        for artifact in artifacts {
            try verifyArtifact(artifact, operations: operations)
            verifiedArtifactIds.append(artifact.id)
        }

        return VerifiedUpdateBootstrapClosure(
            updateId: input.envelope.id,
            canonicalPayloadSHA256: canonicalPayloadSHA256,
            verifiedBootstrapArtifactIds: verifiedArtifactIds,
            verifiedPayloadArtifactIds: []
        )
    }

    private func verifyArtifact(
        _ artifact: UpdateBootstrapArtifact,
        operations: VerifyUpdateBootstrapEnvelopeOperations
    ) throws {
        switch operations.observeArtifact(artifact) {
        case .available(let actualSHA256, let actualSizeBytes):
            guard actualSHA256 == artifact.sha256 else {
                throw VerifyUpdateBootstrapEnvelopeError.artifactDigestMismatch(
                    artifactId: artifact.id,
                    expected: artifact.sha256,
                    actual: actualSHA256
                )
            }
            guard actualSizeBytes == artifact.sizeBytes else {
                throw VerifyUpdateBootstrapEnvelopeError.artifactSizeMismatch(
                    artifactId: artifact.id,
                    expected: artifact.sizeBytes,
                    actual: actualSizeBytes
                )
            }
        case .unavailable(let reason):
            throw VerifyUpdateBootstrapEnvelopeError.artifactUnavailable(
                artifactId: artifact.id,
                reason: reason
            )
        case .failed(let reason):
            throw VerifyUpdateBootstrapEnvelopeError.artifactInspectionFailed(
                artifactId: artifact.id,
                reason: reason
            )
        }
    }
}
