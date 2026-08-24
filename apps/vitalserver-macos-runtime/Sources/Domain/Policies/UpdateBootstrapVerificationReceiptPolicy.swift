import Contracts

public enum UpdateBootstrapVerificationReceiptValidationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSchemaVersion(String)
    case unexpectedCommand(String)
    case invalidUpdateId(String)
    case invalidCanonicalPayloadSHA256(String)
    case invalidResolvedRuntimeHome(String)
    case invalidTrustStorePath(String)
    case invalidObservedAt(String)
}

public enum UpdateBootstrapVerificationReceiptProofPolicyError:
    Error,
    Equatable,
    Sendable
{
    case identityMismatch(field: String, expected: String, actual: String)
    case runtimeHomeMismatch(expected: String, actual: String)
    case trustStorePathMismatch(expected: String, actual: String)
    case uidMismatch(expected: UInt32, actual: UInt32)
    case euidMismatch(expected: UInt32, actual: UInt32)
}

public enum UpdateBootstrapVerificationReceiptPolicy {
    public static func validate(
        _ receipt: UpdateBootstrapVerificationReceipt
    ) throws {
        guard receipt.schemaVersion
            == UpdateBootstrapVerificationReceiptContract.schemaVersion else {
            throw UpdateBootstrapVerificationReceiptValidationError
                .unsupportedSchemaVersion(receipt.schemaVersion)
        }
        guard receipt.command
            == UpdateBootstrapVerificationReceiptContract.command else {
            throw UpdateBootstrapVerificationReceiptValidationError
                .unexpectedCommand(receipt.command)
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(receipt.updateId) else {
            throw UpdateBootstrapVerificationReceiptValidationError
                .invalidUpdateId(receipt.updateId)
        }
        guard isSHA256(receipt.canonicalPayloadSHA256) else {
            throw UpdateBootstrapVerificationReceiptValidationError
                .invalidCanonicalPayloadSHA256(receipt.canonicalPayloadSHA256)
        }
        guard isAbsolutePath(receipt.resolvedRuntimeHome) else {
            throw UpdateBootstrapVerificationReceiptValidationError
                .invalidResolvedRuntimeHome(receipt.resolvedRuntimeHome)
        }
        guard isAbsolutePath(receipt.trustStorePath) else {
            throw UpdateBootstrapVerificationReceiptValidationError
                .invalidTrustStorePath(receipt.trustStorePath)
        }
        guard UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
            receipt.observedAt
        ) else {
            throw UpdateBootstrapVerificationReceiptValidationError
                .invalidObservedAt(receipt.observedAt)
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func isAbsolutePath(_ value: String) -> Bool {
        !value.isEmpty && value.hasPrefix("/") && !value.contains("\0")
    }
}

public enum UpdateBootstrapVerificationReceiptProofPolicy {
    public static func prove(
        receipt: UpdateBootstrapVerificationReceipt,
        expectedUpdateId: String,
        expectedCanonicalPayloadSHA256: String,
        expectedResolvedRuntimeHome: String,
        expectedTrustStorePath: String,
        expectedUid: UInt32,
        expectedEuid: UInt32
    ) throws {
        try UpdateBootstrapVerificationReceiptPolicy.validate(receipt)
        try requireEqual(
            field: "updateId",
            expected: expectedUpdateId,
            actual: receipt.updateId
        )
        try requireEqual(
            field: "canonicalPayloadSHA256",
            expected: expectedCanonicalPayloadSHA256,
            actual: receipt.canonicalPayloadSHA256
        )
        guard receipt.resolvedRuntimeHome == expectedResolvedRuntimeHome else {
            throw UpdateBootstrapVerificationReceiptProofPolicyError
                .runtimeHomeMismatch(
                    expected: expectedResolvedRuntimeHome,
                    actual: receipt.resolvedRuntimeHome
                )
        }
        guard receipt.trustStorePath == expectedTrustStorePath else {
            throw UpdateBootstrapVerificationReceiptProofPolicyError
                .trustStorePathMismatch(
                    expected: expectedTrustStorePath,
                    actual: receipt.trustStorePath
                )
        }
        guard receipt.uid == expectedUid else {
            throw UpdateBootstrapVerificationReceiptProofPolicyError
                .uidMismatch(expected: expectedUid, actual: receipt.uid)
        }
        guard receipt.euid == expectedEuid else {
            throw UpdateBootstrapVerificationReceiptProofPolicyError
                .euidMismatch(expected: expectedEuid, actual: receipt.euid)
        }
    }

    private static func requireEqual(
        field: String,
        expected: String,
        actual: String
    ) throws {
        guard expected == actual else {
            throw UpdateBootstrapVerificationReceiptProofPolicyError
                .identityMismatch(
                    field: field,
                    expected: expected,
                    actual: actual
                )
        }
    }
}
