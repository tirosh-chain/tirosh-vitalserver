import Contracts

public enum PlatformAgentUpdateBootstrapVerificationValidationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSchemaVersion(String)
    case unexpectedProducer(String)
    case invalidVerificationInvocationId(String)
    case invalidBundlePath(String)
    case invalidObservedAt(String)
    case unsupportedState(String)
    case unexpectedField(String)
    case missingField(String)
    case invalidUpdateId(String)
    case invalidCanonicalPayloadSHA256(String)
    case invalidSpawnFailureReason(String)
    case invalidBindingPath(String)
    case invalidBindingFailureReason(String)
    case invalidBindingPathState(String)
    case invalidIdentityField(String)
    case invalidIdentityExpected(String)
    case invalidIdentityActual(String)
}

public enum PlatformAgentUpdateBootstrapVerificationProofPolicyError:
    Error,
    Equatable,
    Sendable
{
    case identityMismatch(field: String, expected: String, actual: String)
    case invoked
    case spawnFailed(reason: String)
    case commandFailed(exitCode: Int32)
    case bindingMissing(path: String)
    case bindingInspectionFailed(path: String, reason: String)
    case bindingPermissionDenied(path: String, reason: String)
    case bindingReadFailed(path: String, reason: String)
    case bindingDecodeFailed(path: String, reason: String)
    case bindingUnexpectedPathState(path: String, state: String)
    case bindingInvalid(reason: String)
    case bindingIdentityMismatch(field: String, expected: String, actual: String)
}

public enum PlatformAgentUpdateBootstrapVerificationSpawnResult:
    Equatable,
    Sendable
{
    case spawnFailed(reason: String)
    case completed(exitCode: Int32)
}

public enum PlatformAgentUpdateBootstrapVerificationOutcome:
    Equatable,
    Sendable
{
    case spawnFailed(reason: String)
    case commandFailed(exitCode: Int32)
    case bindingMissing(path: String)
    case bindingInspectionFailed(path: String, reason: String)
    case bindingPermissionDenied(path: String, reason: String)
    case bindingReadFailed(path: String, reason: String)
    case bindingDecodeFailed(path: String, reason: String)
    case bindingUnexpectedPathState(path: String, state: String)
    case bindingInvalid(reason: String)
    case bindingIdentityMismatch(field: String, expected: String, actual: String)
    case succeeded(updateId: String, canonicalPayloadSHA256: String)
}

public enum PlatformAgentUpdateBootstrapVerificationPolicy {
    public static func validate(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        guard evidence.schemaVersion
            == PlatformAgentUpdateBootstrapVerificationContract.schemaVersion
        else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .unsupportedSchemaVersion(evidence.schemaVersion)
        }
        guard evidence.producer
            == PlatformAgentUpdateBootstrapVerificationContract.producer else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .unexpectedProducer(evidence.producer)
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(
            evidence.verificationInvocationId
        ) else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidVerificationInvocationId(
                    evidence.verificationInvocationId
                )
        }
        guard isAbsolutePath(evidence.bundlePath) else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBundlePath(evidence.bundlePath)
        }
        guard UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
            evidence.observedAt
        ) else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidObservedAt(evidence.observedAt)
        }
        switch evidence.state {
        case PlatformAgentUpdateBootstrapVerificationContract.stateInvoked:
            try requireAbsentIdentity(evidence)
            try requireAbsentCommandAndSpawn(evidence)
            try requireAbsentBindingDetails(evidence)
        case PlatformAgentUpdateBootstrapVerificationContract.stateSpawnFailed:
            try requireAbsentIdentity(evidence)
            try requireAbsent(evidence.exitCode, field: "exitCode")
            try requireAbsentBindingDetails(evidence)
            try requirePresentReason(
                evidence.spawnFailureReason,
                missing: .missingField("spawnFailureReason"),
                invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                    .invalidSpawnFailureReason
            )
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateCommandFailed:
            try requireAbsentIdentity(evidence)
            try requireAbsent(
                evidence.spawnFailureReason,
                field: "spawnFailureReason"
            )
            try requireAbsentBindingDetails(evidence)
            guard evidence.exitCode != nil else {
                throw PlatformAgentUpdateBootstrapVerificationValidationError
                    .missingField("exitCode")
            }
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingMissing:
            try requireBindingPathOnly(evidence)
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingInspectionFailed,
             PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingPermissionDenied,
             PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingReadFailed,
             PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingDecodeFailed:
            try requireBindingPathAndReason(evidence)
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingUnexpectedPathState:
            try requireBindingUnexpectedPathState(evidence)
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingInvalid:
            try requireBindingInvalid(evidence)
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingIdentityMismatch:
            try requireBindingIdentityMismatch(evidence)
        case PlatformAgentUpdateBootstrapVerificationContract.stateSucceeded:
            try requireAbsentCommandAndSpawn(evidence)
            try requireAbsentBindingDetails(evidence)
            try requireSucceededIdentity(evidence)
        default:
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .unsupportedState(evidence.state)
        }
    }

    public static func invoked(
        verificationInvocationId: String,
        bundlePath: String,
        observedAt: String
    ) -> PlatformAgentUpdateBootstrapVerificationEvidence {
        PlatformAgentUpdateBootstrapVerificationEvidence(
            schemaVersion:
                PlatformAgentUpdateBootstrapVerificationContract.schemaVersion,
            producer: PlatformAgentUpdateBootstrapVerificationContract.producer,
            verificationInvocationId: verificationInvocationId,
            bundlePath: bundlePath,
            observedAt: observedAt,
            state: PlatformAgentUpdateBootstrapVerificationContract.stateInvoked
        )
    }

    public static func evidence(
        from invoked: PlatformAgentUpdateBootstrapVerificationEvidence,
        outcome: PlatformAgentUpdateBootstrapVerificationOutcome
    ) -> PlatformAgentUpdateBootstrapVerificationEvidence {
        switch outcome {
        case .spawnFailed(let reason):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract.stateSpawnFailed,
                spawnFailureReason: reason)
        case .commandFailed(let exitCode):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateCommandFailed,
                exitCode: exitCode)
        case .bindingMissing(let path):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateBindingMissing,
                bindingPath: path)
        case .bindingInspectionFailed(let path, let reason):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateBindingInspectionFailed,
                bindingPath: path,
                bindingFailureReason: reason)
        case .bindingPermissionDenied(let path, let reason):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateBindingPermissionDenied,
                bindingPath: path,
                bindingFailureReason: reason)
        case .bindingReadFailed(let path, let reason):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateBindingReadFailed,
                bindingPath: path,
                bindingFailureReason: reason)
        case .bindingDecodeFailed(let path, let reason):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateBindingDecodeFailed,
                bindingPath: path,
                bindingFailureReason: reason)
        case .bindingUnexpectedPathState(let path, let state):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateBindingUnexpectedPathState,
                bindingPath: path,
                bindingPathState: state)
        case .bindingInvalid(let reason):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateBindingInvalid,
                bindingFailureReason: reason)
        case .bindingIdentityMismatch(let field, let expected, let actual):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract
                .stateBindingIdentityMismatch,
                identityField: field,
                identityExpected: expected,
                identityActual: actual)
        case .succeeded(let updateId, let digest):
            return base(invoked, state:
                PlatformAgentUpdateBootstrapVerificationContract.stateSucceeded,
                updateId: updateId,
                canonicalPayloadSHA256: digest)
        }
    }

    public static func outcome(
        spawn: PlatformAgentUpdateBootstrapVerificationSpawnResult,
        expectedVerificationInvocationId: String,
        bindingRead: UpdateBootstrapVerificationInvocationBindingReadInput
    ) -> PlatformAgentUpdateBootstrapVerificationOutcome {
        switch spawn {
        case .spawnFailed(let reason):
            return .spawnFailed(reason: reason)
        case .completed(let exitCode):
            guard exitCode == 0 else {
                return .commandFailed(exitCode: exitCode)
            }
            return correlateBinding(
                expectedVerificationInvocationId:
                    expectedVerificationInvocationId,
                bindingRead: bindingRead
            )
        }
    }

    private static func correlateBinding(
        expectedVerificationInvocationId: String,
        bindingRead: UpdateBootstrapVerificationInvocationBindingReadInput
    ) -> PlatformAgentUpdateBootstrapVerificationOutcome {
        switch bindingRead {
        case .missing(let path):
            return .bindingMissing(path: path)
        case .inspectionFailed(let path, let reason):
            return .bindingInspectionFailed(path: path, reason: reason)
        case .permissionDenied(let path, let reason):
            return .bindingPermissionDenied(path: path, reason: reason)
        case .readFailed(let path, let reason):
            return .bindingReadFailed(path: path, reason: reason)
        case .decodeFailed(let path, let reason):
            return .bindingDecodeFailed(path: path, reason: reason)
        case .unexpectedPathState(let path, let state):
            return .bindingUnexpectedPathState(path: path, state: state)
        case .loaded(let binding):
            do {
                try UpdateBootstrapVerificationInvocationBindingProofPolicy
                    .prove(
                        binding: binding,
                        expectedVerificationInvocationId:
                            expectedVerificationInvocationId,
                        expectedUpdateId: binding.updateId,
                        expectedCanonicalPayloadSHA256:
                            binding.canonicalPayloadSHA256
                    )
                return .succeeded(
                    updateId: binding.updateId,
                    canonicalPayloadSHA256: binding.canonicalPayloadSHA256
                )
            } catch let error as
                UpdateBootstrapVerificationInvocationBindingValidationError
            {
                return .bindingInvalid(reason: String(describing: error))
            } catch let error as
                UpdateBootstrapVerificationInvocationBindingProofPolicyError
            {
                switch error {
                case .identityMismatch(let field, let expected, let actual):
                    return .bindingIdentityMismatch(
                        field: field,
                        expected: expected,
                        actual: actual
                    )
                }
            } catch {
                return .bindingInvalid(reason: String(describing: error))
            }
        }
    }

    private static func base(
        _ invoked: PlatformAgentUpdateBootstrapVerificationEvidence,
        state: String,
        updateId: String? = nil,
        canonicalPayloadSHA256: String? = nil,
        exitCode: Int32? = nil,
        spawnFailureReason: String? = nil,
        bindingPath: String? = nil,
        bindingFailureReason: String? = nil,
        bindingPathState: String? = nil,
        identityField: String? = nil,
        identityExpected: String? = nil,
        identityActual: String? = nil
    ) -> PlatformAgentUpdateBootstrapVerificationEvidence {
        PlatformAgentUpdateBootstrapVerificationEvidence(
            schemaVersion: invoked.schemaVersion,
            producer: invoked.producer,
            verificationInvocationId: invoked.verificationInvocationId,
            bundlePath: invoked.bundlePath,
            observedAt: invoked.observedAt,
            state: state,
            updateId: updateId,
            canonicalPayloadSHA256: canonicalPayloadSHA256,
            exitCode: exitCode,
            spawnFailureReason: spawnFailureReason,
            bindingPath: bindingPath,
            bindingFailureReason: bindingFailureReason,
            bindingPathState: bindingPathState,
            identityField: identityField,
            identityExpected: identityExpected,
            identityActual: identityActual
        )
    }

    private static func requireSucceededIdentity(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        guard let updateId = evidence.updateId else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .missingField("updateId")
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(updateId) else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidUpdateId(updateId)
        }
        guard let digest = evidence.canonicalPayloadSHA256 else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .missingField("canonicalPayloadSHA256")
        }
        guard isSHA256(digest) else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidCanonicalPayloadSHA256(digest)
        }
    }

    private static func requireBindingPathOnly(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsentIdentity(evidence)
        try requireAbsentCommandAndSpawn(evidence)
        try requireAbsent(
            evidence.bindingFailureReason,
            field: "bindingFailureReason"
        )
        try requireAbsent(evidence.bindingPathState, field: "bindingPathState")
        try requireAbsentIdentityMismatchFields(evidence)
        try requirePresentReason(
            evidence.bindingPath,
            missing: .missingField("bindingPath"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingPath
        )
        guard isAbsolutePath(evidence.bindingPath ?? "") else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingPath(evidence.bindingPath ?? "")
        }
    }

    private static func requireBindingPathAndReason(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsentIdentity(evidence)
        try requireAbsentCommandAndSpawn(evidence)
        try requireAbsent(evidence.bindingPathState, field: "bindingPathState")
        try requireAbsentIdentityMismatchFields(evidence)
        try requirePresentReason(
            evidence.bindingPath,
            missing: .missingField("bindingPath"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingPath
        )
        guard isAbsolutePath(evidence.bindingPath ?? "") else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingPath(evidence.bindingPath ?? "")
        }
        try requirePresentReason(
            evidence.bindingFailureReason,
            missing: .missingField("bindingFailureReason"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingFailureReason
        )
    }

    private static func requireBindingUnexpectedPathState(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsentIdentity(evidence)
        try requireAbsentCommandAndSpawn(evidence)
        try requireAbsent(
            evidence.bindingFailureReason,
            field: "bindingFailureReason"
        )
        try requireAbsentIdentityMismatchFields(evidence)
        try requirePresentReason(
            evidence.bindingPath,
            missing: .missingField("bindingPath"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingPath
        )
        guard isAbsolutePath(evidence.bindingPath ?? "") else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingPath(evidence.bindingPath ?? "")
        }
        try requirePresentReason(
            evidence.bindingPathState,
            missing: .missingField("bindingPathState"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingPathState
        )
    }

    private static func requireBindingInvalid(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsentIdentity(evidence)
        try requireAbsentCommandAndSpawn(evidence)
        try requireAbsent(evidence.bindingPath, field: "bindingPath")
        try requireAbsent(evidence.bindingPathState, field: "bindingPathState")
        try requireAbsentIdentityMismatchFields(evidence)
        try requirePresentReason(
            evidence.bindingFailureReason,
            missing: .missingField("bindingFailureReason"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidBindingFailureReason
        )
    }

    private static func requireBindingIdentityMismatch(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsentIdentity(evidence)
        try requireAbsentCommandAndSpawn(evidence)
        try requireAbsent(evidence.bindingPath, field: "bindingPath")
        try requireAbsent(
            evidence.bindingFailureReason,
            field: "bindingFailureReason"
        )
        try requireAbsent(evidence.bindingPathState, field: "bindingPathState")
        try requirePresentReason(
            evidence.identityField,
            missing: .missingField("identityField"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidIdentityField
        )
        try requirePresentReason(
            evidence.identityExpected,
            missing: .missingField("identityExpected"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidIdentityExpected
        )
        try requirePresentReason(
            evidence.identityActual,
            missing: .missingField("identityActual"),
            invalid: PlatformAgentUpdateBootstrapVerificationValidationError
                .invalidIdentityActual
        )
    }

    private static func requireAbsentIdentity(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsent(evidence.updateId, field: "updateId")
        try requireAbsent(
            evidence.canonicalPayloadSHA256,
            field: "canonicalPayloadSHA256"
        )
    }

    private static func requireAbsentCommandAndSpawn(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsent(evidence.exitCode, field: "exitCode")
        try requireAbsent(
            evidence.spawnFailureReason,
            field: "spawnFailureReason"
        )
    }

    private static func requireAbsentBindingDetails(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsent(evidence.bindingPath, field: "bindingPath")
        try requireAbsent(
            evidence.bindingFailureReason,
            field: "bindingFailureReason"
        )
        try requireAbsent(evidence.bindingPathState, field: "bindingPathState")
        try requireAbsentIdentityMismatchFields(evidence)
    }

    private static func requireAbsentIdentityMismatchFields(
        _ evidence: PlatformAgentUpdateBootstrapVerificationEvidence
    ) throws {
        try requireAbsent(evidence.identityField, field: "identityField")
        try requireAbsent(evidence.identityExpected, field: "identityExpected")
        try requireAbsent(evidence.identityActual, field: "identityActual")
    }

    private static func requireAbsent<T>(
        _ value: T?,
        field: String
    ) throws {
        guard value == nil else {
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .unexpectedField(field)
        }
    }

    private static func requirePresentReason(
        _ value: String?,
        missing: PlatformAgentUpdateBootstrapVerificationValidationError,
        invalid: (String) -> PlatformAgentUpdateBootstrapVerificationValidationError
    ) throws {
        guard let value else {
            throw missing
        }
        guard !value.isEmpty else {
            throw invalid(value)
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

public enum PlatformAgentUpdateBootstrapVerificationProofPolicy {
    public static func prove(
        evidence: PlatformAgentUpdateBootstrapVerificationEvidence,
        expectedVerificationInvocationId: String,
        expectedUpdateId: String,
        expectedCanonicalPayloadSHA256: String
    ) throws {
        try PlatformAgentUpdateBootstrapVerificationPolicy.validate(evidence)
        try requireEqual(
            field: "verificationInvocationId",
            expected: expectedVerificationInvocationId,
            actual: evidence.verificationInvocationId
        )
        switch evidence.state {
        case PlatformAgentUpdateBootstrapVerificationContract.stateSucceeded:
            try requireEqual(
                field: "updateId",
                expected: expectedUpdateId,
                actual: evidence.updateId ?? ""
            )
            try requireEqual(
                field: "canonicalPayloadSHA256",
                expected: expectedCanonicalPayloadSHA256,
                actual: evidence.canonicalPayloadSHA256 ?? ""
            )
        case PlatformAgentUpdateBootstrapVerificationContract.stateInvoked:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .invoked
        case PlatformAgentUpdateBootstrapVerificationContract.stateSpawnFailed:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .spawnFailed(reason: evidence.spawnFailureReason ?? "")
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateCommandFailed:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .commandFailed(exitCode: evidence.exitCode ?? 0)
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingMissing:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .bindingMissing(path: evidence.bindingPath ?? "")
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingInspectionFailed:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .bindingInspectionFailed(
                    path: evidence.bindingPath ?? "",
                    reason: evidence.bindingFailureReason ?? ""
                )
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingPermissionDenied:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .bindingPermissionDenied(
                    path: evidence.bindingPath ?? "",
                    reason: evidence.bindingFailureReason ?? ""
                )
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingReadFailed:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .bindingReadFailed(
                    path: evidence.bindingPath ?? "",
                    reason: evidence.bindingFailureReason ?? ""
                )
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingDecodeFailed:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .bindingDecodeFailed(
                    path: evidence.bindingPath ?? "",
                    reason: evidence.bindingFailureReason ?? ""
                )
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingUnexpectedPathState:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .bindingUnexpectedPathState(
                    path: evidence.bindingPath ?? "",
                    state: evidence.bindingPathState ?? ""
                )
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingInvalid:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .bindingInvalid(reason: evidence.bindingFailureReason ?? "")
        case PlatformAgentUpdateBootstrapVerificationContract
            .stateBindingIdentityMismatch:
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .bindingIdentityMismatch(
                    field: evidence.identityField ?? "",
                    expected: evidence.identityExpected ?? "",
                    actual: evidence.identityActual ?? ""
                )
        default:
            throw PlatformAgentUpdateBootstrapVerificationValidationError
                .unsupportedState(evidence.state)
        }
    }

    private static func requireEqual(
        field: String,
        expected: String,
        actual: String
    ) throws {
        guard expected == actual else {
            throw PlatformAgentUpdateBootstrapVerificationProofPolicyError
                .identityMismatch(
                    field: field,
                    expected: expected,
                    actual: actual
                )
        }
    }
}

public enum UpdateBootstrapVerificationInvocationBindingReadInput:
    Equatable,
    Sendable
{
    case missing(path: String)
    case loaded(UpdateBootstrapVerificationInvocationBinding)
    case inspectionFailed(path: String, reason: String)
    case permissionDenied(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}
