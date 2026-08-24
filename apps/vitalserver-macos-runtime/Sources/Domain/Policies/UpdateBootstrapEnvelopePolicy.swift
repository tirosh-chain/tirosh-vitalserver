import Contracts
import Foundation

public enum UpdateBootstrapEnvelopeValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(String)
    case invalidIdentifier(field: String, value: String)
    case productMismatch(expected: String, actual: String)
    case targetMismatch(expected: UpdateBootstrapTarget, actual: UpdateBootstrapTarget)
    case invalidReleaseVersion(field: String, value: String)
    case emptyLayerOrder
    case tooManyLayers(Int)
    case duplicateLayer(UpdateLayer)
    case hostPlatformMustBeLast
    case invalidArtifactPath(artifactId: String, relativePath: String)
    case invalidArtifactSHA256(artifactId: String, sha256: String)
    case invalidArtifactSize(artifactId: String, sizeBytes: Int)
    case invalidArtifactMediaType(artifactId: String)
    case emptyPayloadArtifacts
    case duplicatePayloadArtifactPath(String)
    case duplicatePayloadArtifactId(String)
    case payloadArtifactConflictsWithBootstrap(relativePath: String)
    case invalidSignatureKeyId(String)
    case invalidSignatureSHA256(String)
    case emptySignature
    case invalidIssuedAt(String)
}

public enum UpdateBootstrapEnvelopePolicy {
    public static func validate(
        _ envelope: UpdateBootstrapEnvelope,
        expectedProductId: String,
        expectedTarget: UpdateBootstrapTarget
    ) throws {
        guard envelope.schemaVersion == "v2" else {
            throw UpdateBootstrapEnvelopeValidationError.unsupportedSchemaVersion(
                envelope.schemaVersion
            )
        }
        try requireIdentifier(envelope.id, field: "id")
        try requireIdentifier(envelope.productId, field: "productId")
        guard envelope.productId == expectedProductId else {
            throw UpdateBootstrapEnvelopeValidationError.productMismatch(
                expected: expectedProductId,
                actual: envelope.productId
            )
        }
        guard envelope.target == expectedTarget else {
            throw UpdateBootstrapEnvelopeValidationError.targetMismatch(
                expected: expectedTarget,
                actual: envelope.target
            )
        }
        try requireVersion(
            envelope.targetRelease.productVersion,
            field: "targetRelease.productVersion"
        )
        try requireVersion(
            envelope.targetRelease.runtimeVersion,
            field: "targetRelease.runtimeVersion"
        )
        try validateLayerOrder(envelope.layerOrder)
        try validateArtifact(envelope.nextUpdaterArtifact)
        try validateArtifact(envelope.specification)
        try validatePayloadArtifacts(envelope)
        try requireIdentifier(envelope.signature.keyId, field: "signature.keyId")
        guard isSHA256(envelope.signature.signedSha256) else {
            throw UpdateBootstrapEnvelopeValidationError.invalidSignatureSHA256(
                envelope.signature.signedSha256
            )
        }
        guard !envelope.signature.value.isEmpty else {
            throw UpdateBootstrapEnvelopeValidationError.emptySignature
        }
        guard isCanonicalTimestamp(envelope.issuedAt) else {
            throw UpdateBootstrapEnvelopeValidationError.invalidIssuedAt(
                envelope.issuedAt
            )
        }
    }

    private static func validatePayloadArtifacts(
        _ envelope: UpdateBootstrapEnvelope
    ) throws {
        guard !envelope.payloadArtifacts.isEmpty else {
            throw UpdateBootstrapEnvelopeValidationError.emptyPayloadArtifacts
        }
        var observedPaths = Set<String>()
        var observedIds = Set<String>()
        for artifact in envelope.payloadArtifacts {
            try validateArtifact(artifact)
            guard observedPaths.insert(artifact.relativePath).inserted else {
                throw UpdateBootstrapEnvelopeValidationError
                    .duplicatePayloadArtifactPath(artifact.relativePath)
            }
            guard observedIds.insert(artifact.id).inserted else {
                throw UpdateBootstrapEnvelopeValidationError
                    .duplicatePayloadArtifactId(artifact.id)
            }
        }
        let bootstrapPaths = Set([
            envelope.nextUpdaterArtifact.relativePath,
            envelope.specification.relativePath,
        ])
        for path in observedPaths where bootstrapPaths.contains(path) {
            throw UpdateBootstrapEnvelopeValidationError
                .payloadArtifactConflictsWithBootstrap(relativePath: path)
        }
    }

    private static func validateLayerOrder(_ layers: [UpdateLayer]) throws {
        guard !layers.isEmpty else {
            throw UpdateBootstrapEnvelopeValidationError.emptyLayerOrder
        }
        guard layers.count <= 3 else {
            throw UpdateBootstrapEnvelopeValidationError.tooManyLayers(layers.count)
        }
        var observed = Set<UpdateLayer>()
        for layer in layers {
            guard observed.insert(layer).inserted else {
                throw UpdateBootstrapEnvelopeValidationError.duplicateLayer(layer)
            }
        }
        if let hostIndex = layers.firstIndex(of: .hostPlatform),
           hostIndex != layers.index(before: layers.endIndex) {
            throw UpdateBootstrapEnvelopeValidationError.hostPlatformMustBeLast
        }
    }

    private static func validateArtifact(_ artifact: UpdateBootstrapArtifact) throws {
        try requireIdentifier(artifact.id, field: "artifact.id")
        let components = artifact.relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard artifact.relativePath.hasPrefix("payload/"),
              components.count >= 2,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !artifact.relativePath.contains("\\"),
              isAllowedASCII(
                  artifact.relativePath,
                  allowedPunctuation: "._/-"
              ) else {
            throw UpdateBootstrapEnvelopeValidationError.invalidArtifactPath(
                artifactId: artifact.id,
                relativePath: artifact.relativePath
            )
        }
        guard isSHA256(artifact.sha256) else {
            throw UpdateBootstrapEnvelopeValidationError.invalidArtifactSHA256(
                artifactId: artifact.id,
                sha256: artifact.sha256
            )
        }
        guard artifact.sizeBytes > 0 else {
            throw UpdateBootstrapEnvelopeValidationError.invalidArtifactSize(
                artifactId: artifact.id,
                sizeBytes: artifact.sizeBytes
            )
        }
        let mediaTypeParts = artifact.mediaType.split(separator: "/")
        guard mediaTypeParts.count == 2,
              isAllowedASCII(
                  artifact.mediaType,
                  allowedPunctuation: ".+-/"
              ) else {
            throw UpdateBootstrapEnvelopeValidationError.invalidArtifactMediaType(
                artifactId: artifact.id
            )
        }
    }

    private static func requireIdentifier(_ value: String, field: String) throws {
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(value) else {
            throw UpdateBootstrapEnvelopeValidationError.invalidIdentifier(
                field: field,
                value: value
            )
        }
    }

    private static func requireVersion(_ value: String, field: String) throws {
        guard UpdateBootstrapIdentifierSyntax.isVersion(value) else {
            throw UpdateBootstrapEnvelopeValidationError.invalidReleaseVersion(
                field: field,
                value: value
            )
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func isAllowedASCII(
        _ value: String,
        allowedPunctuation: String
    ) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            let isUppercaseLetter = (65...90).contains(code)
            let isLowercaseLetter = (97...122).contains(code)
            let isDigit = (48...57).contains(code)
            return isUppercaseLetter
                || isLowercaseLetter
                || isDigit
                || allowedPunctuation.unicodeScalars.contains(scalar)
        }
    }

    private static func isCanonicalTimestamp(_ value: String) -> Bool {
        guard value.count == 20,
              value[value.index(value.startIndex, offsetBy: 4)] == "-",
              value[value.index(value.startIndex, offsetBy: 7)] == "-",
              value[value.index(value.startIndex, offsetBy: 10)] == "T",
              value[value.index(value.startIndex, offsetBy: 13)] == ":",
              value[value.index(value.startIndex, offsetBy: 16)] == ":",
              value.hasSuffix("Z") else {
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else {
            return false
        }
        return formatter.string(from: date) == value
    }
}
