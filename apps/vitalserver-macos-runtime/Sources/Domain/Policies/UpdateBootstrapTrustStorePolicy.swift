import Contracts

public enum UpdateBootstrapTrustStoreValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(String)
    case emptyKeys
    case tooManyKeys(Int)
    case invalidKeyId(String)
    case duplicateKeyId(String)
    case invalidPublicKey(keyId: String)
}

public enum UpdateBootstrapTrustStorePolicy {
    public static func validate(_ store: UpdateBootstrapTrustStore) throws {
        guard store.schemaVersion == "v2" else {
            throw UpdateBootstrapTrustStoreValidationError.unsupportedSchemaVersion(
                store.schemaVersion
            )
        }
        guard !store.keys.isEmpty else {
            throw UpdateBootstrapTrustStoreValidationError.emptyKeys
        }
        guard store.keys.count <= 128 else {
            throw UpdateBootstrapTrustStoreValidationError.tooManyKeys(
                store.keys.count
            )
        }

        var observedKeyIds = Set<String>()
        for key in store.keys {
            guard isIdentifier(key.id) else {
                throw UpdateBootstrapTrustStoreValidationError.invalidKeyId(
                    key.id
                )
            }
            guard observedKeyIds.insert(key.id).inserted else {
                throw UpdateBootstrapTrustStoreValidationError.duplicateKeyId(
                    key.id
                )
            }
            guard key.publicKey.count == 44,
                  key.publicKey.hasSuffix("="),
                  key.publicKey.dropLast().allSatisfy(isBase64Character) else {
                throw UpdateBootstrapTrustStoreValidationError.invalidPublicKey(
                    keyId: key.id
                )
            }
        }
    }

    private static func isIdentifier(_ value: String) -> Bool {
        UpdateBootstrapIdentifierSyntax.isIdentifier(value)
    }

    private static func isBase64Character(_ character: Character) -> Bool {
        character.isASCII
            && (character.isLetter
                || character.isNumber
                || character == "+"
                || character == "/")
    }
}
