import Contracts

public enum UpdateBootstrapVerificationInvocationBindingValidationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSchemaVersion(String)
    case unexpectedCommand(String)
    case invalidVerificationInvocationId(String)
    case invalidUpdateId(String)
    case invalidCanonicalPayloadSHA256(String)
}

public enum UpdateBootstrapVerificationInvocationBindingProofPolicyError:
    Error,
    Equatable,
    Sendable
{
    case identityMismatch(field: String, expected: String, actual: String)
}

public enum UpdateBootstrapVerificationInvocationBindingPolicy {
    public static func validate(
        _ binding: UpdateBootstrapVerificationInvocationBinding
    ) throws {
        guard binding.schemaVersion
            == UpdateBootstrapVerificationInvocationBindingContract
            .schemaVersion else {
            throw UpdateBootstrapVerificationInvocationBindingValidationError
                .unsupportedSchemaVersion(binding.schemaVersion)
        }
        guard binding.command
            == UpdateBootstrapVerificationInvocationBindingContract.command
        else {
            throw UpdateBootstrapVerificationInvocationBindingValidationError
                .unexpectedCommand(binding.command)
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(
            binding.verificationInvocationId
        ) else {
            throw UpdateBootstrapVerificationInvocationBindingValidationError
                .invalidVerificationInvocationId(
                    binding.verificationInvocationId
                )
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(binding.updateId)
        else {
            throw UpdateBootstrapVerificationInvocationBindingValidationError
                .invalidUpdateId(binding.updateId)
        }
        guard isSHA256(binding.canonicalPayloadSHA256) else {
            throw UpdateBootstrapVerificationInvocationBindingValidationError
                .invalidCanonicalPayloadSHA256(binding.canonicalPayloadSHA256)
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }
}

public enum UpdateBootstrapVerificationInvocationBindingProofPolicy {
    public static func prove(
        binding: UpdateBootstrapVerificationInvocationBinding,
        expectedVerificationInvocationId: String,
        expectedUpdateId: String,
        expectedCanonicalPayloadSHA256: String
    ) throws {
        try UpdateBootstrapVerificationInvocationBindingPolicy.validate(
            binding
        )
        try requireEqual(
            field: "verificationInvocationId",
            expected: expectedVerificationInvocationId,
            actual: binding.verificationInvocationId
        )
        try requireEqual(
            field: "updateId",
            expected: expectedUpdateId,
            actual: binding.updateId
        )
        try requireEqual(
            field: "canonicalPayloadSHA256",
            expected: expectedCanonicalPayloadSHA256,
            actual: binding.canonicalPayloadSHA256
        )
    }

    private static func requireEqual(
        field: String,
        expected: String,
        actual: String
    ) throws {
        guard expected == actual else {
            throw UpdateBootstrapVerificationInvocationBindingProofPolicyError
                .identityMismatch(
                    field: field,
                    expected: expected,
                    actual: actual
                )
        }
    }
}
